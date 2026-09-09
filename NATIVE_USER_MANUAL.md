# Native Windows OpenTrafficCam workflow

This is the active workflow when Docker is unavailable. It uses isolated
Python 3.12 environments and executes OTVision directly on the NVIDIA GPU.

## Installed components

- OTVision `v0.7.2` with PyTorch `2.7.1+cu128`
- OTAnalytics `v0.7.4`
- Managed CPython `3.12.13`
- Local `uv 0.11.28`
- Official `yolov8s.pt` weights in `models`

The native applications are under `native`. Do not manually install packages
into their `.venv` directories.

## Verify the installation

```powershell
cd "C:\Users\Ehsani\Github repos\Traffic_Detection"
.\traffic-native.ps1 preflight
```

The first PyTorch import can take several minutes while security software scans
the new native libraries. Later runs should start faster.

## Create a camera analysis configuration

```powershell
.\traffic-native.ps1 gui
```

In OTAnalytics:

1. Load the matching MP4 and `.ottrk` from `Data\Download`.
2. Draw the virtual sections used as counting lines.
3. Define the desired from-to flows.
4. Inspect track visualization and correct section placement.
5. Export `.otflow` or `.otconfig` into `config\analytics`.

Create and validate a separate configuration for every fixed camera view.

## Analyze the existing track first

After creating `camera-v1.otflow`:

```powershell
.\traffic-native.ps1 analytics `
  -TrackFile "Download\Standard_SCUCPX_2024-10-08_0000.009_2024-10-08_08-00-02.ottrk" `
  -AnalysisConfig "camera-v1.otflow" `
  -CountIntervals 5,15,60
```

This validates OTAnalytics without repeating GPU detection.

## Run MP4 to analytics

```powershell
.\traffic-native.ps1 run `
  -InputFile "Download\Standard_SCUCPX_2024-10-08_0000.009_2024-10-08_08-00-02.mp4" `
  -AnalysisConfig "camera-v1.otflow" `
  -CountIntervals 5,15,60
```

Use `-Force` only when intentionally replacing existing `.otdet` and `.ottrk`
files. Without it, the controller passes no-overwrite to OTVision.

## Individual stages

Detection and tracking only:

```powershell
.\traffic-native.ps1 vision `
  -InputFile "Download\video_2026-07-16_08-00-00.mp4"
```

Analytics only:

```powershell
.\traffic-native.ps1 analytics `
  -TrackFile "Download\video_2026-07-16_08-00-00.ottrk" `
  -AnalysisConfig "camera-v1.otflow"
```

Outputs are written to `Data\Output\<track-name>` with a
`job-manifest.json` audit record.

OTAnalytics `v0.7.4` performs this CLI analysis without the legacy
`--num-processes` option; the native controller intentionally does not pass it.

## Notes

- `nvcc` and a separately installed CUDA Toolkit are not required. The pinned
  PyTorch wheel includes its CUDA 12.8 runtime; a compatible NVIDIA driver is
  required and has been verified.
- The project uses managed Python directly because Windows policy blocks the
  copied Python launcher inside this particular `.venv`. The controller handles
  this workaround automatically.
- Existing CSV files cannot reconstruct the missing `.otflow` geometry.
- OTLabels is not required unless count validation demonstrates systematic
  detector errors that justify custom training.
