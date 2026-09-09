[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('preflight', 'build', 'run', 'vision', 'analytics', 'help')]
    [string]$Action = 'help',

    [ValidateSet('gpu', 'cpu')]
    [string]$Mode = 'gpu',

    [string]$InputFile,
    [string]$TrackFile,
    [string]$AnalysisConfig,
    [string]$Weights = 'yolov8s.pt',
    [int[]]$CountIntervals = @(15),
    [ValidateRange(1, 128)]
    [int]$Processes = 4,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$ComposeFile = Join-Path $ProjectRoot 'compose.yaml'
$DataRoot = Join-Path $ProjectRoot 'Data'
$AnalyticsConfigRoot = Join-Path $ProjectRoot 'config\analytics'

function Show-Usage {
    @'
Traffic Detection pipeline

  .\traffic.ps1 preflight
  .\traffic.ps1 build [-Mode gpu|cpu]
  .\traffic.ps1 run -InputFile "Download\video_2026-01-01_08-00-00.mp4" `
      -AnalysisConfig "camera-a.otflow" [-Mode gpu|cpu]
  .\traffic.ps1 vision -InputFile "Download\video_2026-01-01_08-00-00.mp4"
  .\traffic.ps1 analytics -TrackFile "Download\video_2026-01-01_08-00-00.ottrk" `
      -AnalysisConfig "camera-a.otflow"

All input paths are relative to Data. Analysis configurations are relative to
config\analytics. Absolute paths are accepted only when they stay inside those
directories.
'@ | Write-Host
}

function Assert-Command([string]$Name, [string]$Message) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw $Message
    }
}

function Invoke-Docker([string[]]$DockerArguments) {
    Write-Host "docker $($DockerArguments -join ' ')" -ForegroundColor DarkGray
    & docker @DockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker failed with exit code $LASTEXITCODE."
    }
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

function Convert-ToContainerPath([string]$Root, [string]$Path, [string]$ContainerRoot) {
    $relative = [IO.Path]::GetRelativePath(
        [IO.Path]::GetFullPath($Root),
        [IO.Path]::GetFullPath($Path)
    ).Replace('\', '/')
    return "$ContainerRoot/$relative"
}

function Get-VisionService {
    if ($Mode -eq 'gpu') { return 'otvision-gpu' }
    return 'otvision-cpu'
}

function Assert-Preflight([bool]$RequireDaemon = $true) {
    Assert-Command 'docker' 'Docker is not installed. Install Docker Desktop, enable WSL 2, then reopen PowerShell.'
    if ($RequireDaemon) {
        & docker info *> $null
        if ($LASTEXITCODE -ne 0) {
            throw 'Docker Desktop is installed but its engine is not running.'
        }
    }
    if ($Mode -eq 'gpu') {
        Assert-Command 'nvidia-smi' 'GPU mode requires a working NVIDIA driver. Use -Mode cpu or install the driver.'
        & nvidia-smi --query-gpu=name --format=csv,noheader
        if ($LASTEXITCODE -ne 0) {
            throw 'nvidia-smi failed. Use -Mode cpu or repair the NVIDIA driver.'
        }
    }
}

function Invoke-Vision([string]$VideoArgument) {
    $video = Get-SafePath $DataRoot $VideoArgument
    if ([IO.Path]::GetExtension($video).ToLowerInvariant() -ne '.mp4') {
        throw 'The automated workflow currently accepts .mp4 input.'
    }
    $name = [IO.Path]::GetFileName($video)
    if ($name -notmatch '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}') {
        throw "OTVision requires a YYYY-MM-DD_HH-MM-SS timestamp in the filename: $name"
    }
    $containerVideo = Convert-ToContainerPath $DataRoot $video '/data'
    $overwrite = if ($Force) { '--overwrite' } else { '--no-overwrite' }
    $service = Get-VisionService

    Invoke-Docker @(
        'compose', '--project-directory', $ProjectRoot, '-f', $ComposeFile,
        'run', '--rm', $service,
        'uv', 'run', '--frozen', 'detect.py',
        '--paths', $containerVideo,
        '--weights', $Weights,
        $overwrite
    )

    $detection = [IO.Path]::ChangeExtension($video, '.otdet')
    if (-not (Test-Path -LiteralPath $detection -PathType Leaf)) {
        throw "Detection finished without producing the expected file: $detection"
    }
    $containerDetection = Convert-ToContainerPath $DataRoot $detection '/data'
    Invoke-Docker @(
        'compose', '--project-directory', $ProjectRoot, '-f', $ComposeFile,
        'run', '--rm', $service,
        'uv', 'run', '--frozen', 'track.py',
        '--paths', $containerDetection,
        $overwrite
    )

    $track = [IO.Path]::ChangeExtension($video, '.ottrk')
    if (-not (Test-Path -LiteralPath $track -PathType Leaf)) {
        throw "Tracking finished without producing the expected file: $track"
    }
    return $track
}

function Invoke-Analytics([string]$TrackArgument, [string]$ConfigArgument) {
    $track = Get-SafePath $DataRoot $TrackArgument
    if ([IO.Path]::GetExtension($track).ToLowerInvariant() -ne '.ottrk') {
        throw 'OTAnalytics input must be an .ottrk file.'
    }
    $config = Get-SafePath $AnalyticsConfigRoot $ConfigArgument
    $configExtension = [IO.Path]::GetExtension($config).ToLowerInvariant()
    if ($configExtension -notin @('.otflow', '.otconfig')) {
        throw 'AnalysisConfig must be an .otflow or .otconfig file.'
    }

    $jobName = [IO.Path]::GetFileNameWithoutExtension($track)
    $outputDirectory = Join-Path $DataRoot (Join-Path 'Output' $jobName)
    [void](New-Item -ItemType Directory -Force -Path $outputDirectory)
    $containerTrack = Convert-ToContainerPath $DataRoot $track '/data'
    $containerConfig = Convert-ToContainerPath $AnalyticsConfigRoot $config '/config/analytics'
    $containerOutput = Convert-ToContainerPath $DataRoot $outputDirectory '/data'
    $configSwitch = if ($configExtension -eq '.otconfig') { '--config' } else { '--otflow' }
    $intervalArgs = @('--count-intervals') + ($CountIntervals | ForEach-Object { $_.ToString() })

    $arguments = @(
        'compose', '--project-directory', $ProjectRoot, '-f', $ComposeFile,
        'run', '--rm', 'otanalytics',
        'uv', 'run', '--frozen', 'python', '-m', 'OTAnalytics',
        '--cli', '--ottrks', $containerTrack,
        $configSwitch, $containerConfig,
        '--save-dir', $containerOutput,
        '--save-name', $jobName,
        '--event-formats', 'csv', 'xlsx'
    ) + $intervalArgs + @('--num-processes', $Processes.ToString())
    Invoke-Docker $arguments

    $manifest = [ordered]@{
        job_name = $jobName
        completed_utc = [DateTime]::UtcNow.ToString('o')
        track_file = [IO.Path]::GetRelativePath($ProjectRoot, $track)
        analysis_config = [IO.Path]::GetRelativePath($ProjectRoot, $config)
        output_directory = [IO.Path]::GetRelativePath($ProjectRoot, $outputDirectory)
        count_intervals_minutes = $CountIntervals
        processes = $Processes
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDirectory 'job-manifest.json') -Encoding utf8
    Write-Host "Results: $outputDirectory" -ForegroundColor Green
}

switch ($Action) {
    'help' { Show-Usage; break }
    'preflight' {
        Assert-Preflight
        Invoke-Docker @('compose', '--project-directory', $ProjectRoot, '-f', $ComposeFile, 'config', '--quiet')
        Write-Host 'Preflight passed.' -ForegroundColor Green
        break
    }
    'build' {
        Assert-Preflight
        Invoke-Docker @(
            'compose', '--project-directory', $ProjectRoot, '-f', $ComposeFile,
            'build', (Get-VisionService), 'otanalytics'
        )
        break
    }
    'vision' {
        Assert-Preflight
        if (-not $InputFile) { throw 'vision requires -InputFile.' }
        $result = Invoke-Vision $InputFile
        Write-Host "Track file: $result" -ForegroundColor Green
        break
    }
    'analytics' {
        Assert-Preflight
        if (-not $TrackFile) { throw 'analytics requires -TrackFile.' }
        if (-not $AnalysisConfig) { throw 'analytics requires -AnalysisConfig.' }
        Invoke-Analytics $TrackFile $AnalysisConfig
        break
    }
    'run' {
        Assert-Preflight
        if (-not $InputFile) { throw 'run requires -InputFile.' }
        if (-not $AnalysisConfig) { throw 'run requires -AnalysisConfig.' }
        $createdTrack = Invoke-Vision $InputFile
        Invoke-Analytics $createdTrack $AnalysisConfig
        break
    }
}
