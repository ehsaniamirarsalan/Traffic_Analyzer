# OpenTrafficCam end-to-end pipeline

This project converts timestamped MP4 traffic recordings into OTVision
detections/tracks and OTAnalytics event/count exports.

## Native Windows workflow (active)

Docker is unavailable on this machine, so use the verified native CUDA setup.
Start with `NATIVE_USER_MANUAL.md`:

```powershell
.\traffic-native.ps1 preflight
.\traffic-native.ps1 gui
.\traffic-native.ps1 run `
  -InputFile "Download\your_video_2026-07-14_08-00-00.mp4" `
  -AnalysisConfig "your-camera.otflow"
```

## Docker workflow (optional)

----------------------

```powershell
.\traffic.ps1 preflight
.\traffic.ps1 build -Mode gpu
.\traffic.ps1 run `
  -InputFile "Download\your_video_2026-07-14_08-00-00.mp4" `
  -AnalysisConfig "your-camera.otflow" `
  -Mode gpu
```

The `.otflow` file is a one-time, camera-specific configuration created and
validated in the OTAnalytics desktop GUI. OTLabels is intentionally excluded
from the runtime because pretrained OTVision weights require no training.
