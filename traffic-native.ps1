[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('preflight', 'run', 'vision', 'analytics', 'gui', 'help')]
    [string]$Action = 'help',

    [string]$InputFile,
    [string]$TrackFile,
    [string]$AnalysisConfig,
    [string]$Weights = 'yolov8s.pt',
    [int[]]$CountIntervals = @(15),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$DataRoot = Join-Path $ProjectRoot 'Data'
$ModelsRoot = Join-Path $ProjectRoot 'models'
$AnalyticsConfigRoot = Join-Path $ProjectRoot 'config\analytics'
$VisionRoot = Join-Path $ProjectRoot 'native\OTVision'
$AnalyticsRoot = Join-Path $ProjectRoot 'native\OTAnalytics'
$Uv = Join-Path $ProjectRoot '.tools\uv\uv.exe'

function Show-Usage {
    @'
Native OpenTrafficCam pipeline

  .\traffic-native.ps1 preflight
  .\traffic-native.ps1 gui
  .\traffic-native.ps1 run -InputFile "Download\video_2026-01-01_08-00-00.mp4" `
      -AnalysisConfig "camera-a.otflow"
  .\traffic-native.ps1 vision -InputFile "Download\video_2026-01-01_08-00-00.mp4"
  .\traffic-native.ps1 analytics -TrackFile "Download\video_2026-01-01_08-00-00.ottrk" `
      -AnalysisConfig "camera-a.otflow"

Input and track paths are relative to Data. Analysis configurations are
relative to config\analytics. Custom weights are relative to models.
'@ | Write-Host
}

function Get-SafePath(
    [string]$Root,
    [string]$Value,
    [bool]$MustExist = $true
) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw 'A required path argument is missing.'
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $candidate = if ([IO.Path]::IsPathRooted($Value)) {
        [IO.Path]::GetFullPath($Value)
    } else {
        [IO.Path]::GetFullPath((Join-Path $rootFull $Value))
    }
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -and
        -not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must stay inside '$rootFull': $Value"
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "File does not exist: $candidate"
    }
    return $candidate
}

function Get-ProjectRelativePath([string]$Path) {
    $rootFull = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if ($pathFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($prefix.Length)
    }
    return $pathFull
}

function Get-ManagedPython {
    if (-not (Test-Path -LiteralPath $Uv -PathType Leaf)) {
        throw "Local uv executable is missing: $Uv"
    }
    $lines = & $Uv python find 3.12 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot locate managed Python 3.12: $($lines -join [Environment]::NewLine)"
    }
    foreach ($line in $lines) {
        $candidate = $line.ToString().Trim()
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw 'uv returned no usable Python 3.12 path.'
}

function Invoke-NativePython(
    [string]$Repository,
    [string[]]$PythonArguments
) {
    $python = Get-ManagedPython
    $venv = Join-Path $Repository '.venv'
    $sitePackages = Join-Path $venv 'Lib\site-packages'
    if (-not (Test-Path -LiteralPath $sitePackages -PathType Container)) {
        throw "The environment has not been installed: $venv"
    }

    $oldVirtualEnv = $env:VIRTUAL_ENV
    $oldPythonPath = $env:PYTHONPATH
    $oldPath = $env:PATH
    try {
        $env:VIRTUAL_ENV = $venv
        $env:PYTHONPATH = "$Repository;$sitePackages"
        $env:PATH = "$(Join-Path $venv 'Scripts');$(Split-Path -Parent $python);$oldPath"
        Push-Location $Repository
        try {
            Write-Host "python $($PythonArguments -join ' ')" -ForegroundColor DarkGray
            & $python @PythonArguments
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
    } finally {
        $env:VIRTUAL_ENV = $oldVirtualEnv
        $env:PYTHONPATH = $oldPythonPath
        $env:PATH = $oldPath
    }
    if ($exitCode -ne 0) {
        throw "Python command failed with exit code $exitCode."
    }
}

function Assert-NativeProject {
    foreach ($path in @(
        $Uv,
        (Join-Path $VisionRoot 'detect.py'),
        (Join-Path $VisionRoot 'track.py'),
        (Join-Path $VisionRoot '.venv\Lib\site-packages'),
        (Join-Path $AnalyticsRoot '.venv\Lib\site-packages'),
        (Join-Path $ModelsRoot 'yolov8s.pt')
    )) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Native prerequisite is missing: $path"
        }
    }
}

function Invoke-Preflight {
    Assert-NativeProject
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        throw 'nvidia-smi is missing; install or repair the NVIDIA driver.'
    }
    & nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    if ($LASTEXITCODE -ne 0) { throw 'nvidia-smi failed.' }
    Invoke-NativePython $VisionRoot @(
        '-c',
        "import torch; assert torch.cuda.is_available(), 'CUDA unavailable'; print(f'torch={torch.__version__}'); print(f'cuda={torch.version.cuda}'); print(f'gpu={torch.cuda.get_device_name(0)}')"
    )
    Invoke-NativePython $AnalyticsRoot @('-c', "import OTAnalytics; print('OTAnalytics import OK')")
    Write-Host 'Native preflight passed.' -ForegroundColor Green
}

function Invoke-Vision([string]$VideoArgument) {
    Assert-NativeProject
    $video = Get-SafePath $DataRoot $VideoArgument
    if ([IO.Path]::GetExtension($video).ToLowerInvariant() -ne '.mp4') {
        throw 'The automated native workflow currently accepts .mp4 input.'
    }
    $name = [IO.Path]::GetFileName($video)
    if ($name -notmatch '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}') {
        throw "OTVision requires a YYYY-MM-DD_HH-MM-SS timestamp in the filename: $name"
    }
    $weightsFile = Get-SafePath $ModelsRoot $Weights
    $overwrite = if ($Force) { '--overwrite' } else { '--no-overwrite' }

    Invoke-NativePython $VisionRoot @(
        (Join-Path $VisionRoot 'detect.py'),
        '--paths', $video,
        '--weights', $weightsFile,
        $overwrite
    )
    $detection = [IO.Path]::ChangeExtension($video, '.otdet')
    if (-not (Test-Path -LiteralPath $detection -PathType Leaf)) {
        throw "Detection did not produce the expected file: $detection"
    }

    Invoke-NativePython $VisionRoot @(
        (Join-Path $VisionRoot 'track.py'),
        '--paths', $detection,
        $overwrite
    )
    $track = [IO.Path]::ChangeExtension($video, '.ottrk')
    if (-not (Test-Path -LiteralPath $track -PathType Leaf)) {
        throw "Tracking did not produce the expected file: $track"
    }
    return $track
}

function Invoke-Analytics([string]$TrackArgument, [string]$ConfigArgument) {
    Assert-NativeProject
    $track = Get-SafePath $DataRoot $TrackArgument
    if ([IO.Path]::GetExtension($track).ToLowerInvariant() -ne '.ottrk') {
        throw 'OTAnalytics input must be an .ottrk file.'
    }
    $config = Get-SafePath $AnalyticsConfigRoot $ConfigArgument
    $extension = [IO.Path]::GetExtension($config).ToLowerInvariant()
    if ($extension -notin @('.otflow', '.otconfig')) {
        throw 'AnalysisConfig must be an .otflow or .otconfig file.'
    }

    $jobName = [IO.Path]::GetFileNameWithoutExtension($track)
    $outputDirectory = Join-Path $DataRoot (Join-Path 'Output' $jobName)
    [void](New-Item -ItemType Directory -Force -Path $outputDirectory)
    $configSwitch = if ($extension -eq '.otconfig') { '--config' } else { '--otflow' }
    $intervalArguments = @('--count-intervals') + ($CountIntervals | ForEach-Object { $_.ToString() })
    $arguments = @(
        '-m', 'OTAnalytics', '--cli',
        '--ottrks', $track,
        $configSwitch, $config,
        '--save-dir', $outputDirectory,
        '--save-name', $jobName,
        '--event-formats', 'csv', 'xlsx'
    ) + $intervalArguments
    Invoke-NativePython $AnalyticsRoot $arguments

    $manifest = [ordered]@{
        execution = 'native-windows'
        job_name = $jobName
        completed_utc = [DateTime]::UtcNow.ToString('o')
        track_file = Get-ProjectRelativePath $track
        analysis_config = Get-ProjectRelativePath $config
        output_directory = Get-ProjectRelativePath $outputDirectory
        model = $Weights
        count_intervals_minutes = $CountIntervals
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDirectory 'job-manifest.json') -Encoding utf8
    Write-Host "Results: $outputDirectory" -ForegroundColor Green
}

switch ($Action) {
    'help' { Show-Usage; break }
    'preflight' { Invoke-Preflight; break }
    'gui' {
        Assert-NativeProject
        Write-Host 'OTAnalytics will run until you close its window.' -ForegroundColor Cyan
        Invoke-NativePython $AnalyticsRoot @('-m', 'OTAnalytics')
        break
    }
    'vision' {
        if (-not $InputFile) { throw 'vision requires -InputFile.' }
        $createdTrack = Invoke-Vision $InputFile
        Write-Host "Track file: $createdTrack" -ForegroundColor Green
        break
    }
    'analytics' {
        if (-not $TrackFile) { throw 'analytics requires -TrackFile.' }
        if (-not $AnalysisConfig) { throw 'analytics requires -AnalysisConfig.' }
        Invoke-Analytics $TrackFile $AnalysisConfig
        break
    }
    'run' {
        if (-not $InputFile) { throw 'run requires -InputFile.' }
        if (-not $AnalysisConfig) { throw 'run requires -AnalysisConfig.' }
        $createdTrack = Invoke-Vision $InputFile
        Invoke-Analytics $createdTrack $AnalysisConfig
        break
    }
}
