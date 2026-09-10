# User manual: MP4 to traffic analytics

## 1. What this project does

For each fixed-camera MP4, the workflow runs:

1. **OTVision Detect**: MP4 to `.otdet` object detections.
2. **OTVision Track**: `.otdet` to `.ottrk` road-user trajectories.
3. **OTAnalytics CLI**: `.ottrk` plus a camera configuration to CSV/XLSX
   events, counts, assignments, and statistics.

OTLabels is not a runtime component. Use it only if a measured validation study
shows that the pretrained detector is not accurate enough for your footage.

## 2. Important project locations

| Location | Purpose |
|---|---|
| `Data\Download` | Existing videos, metadata, tracks, and reference outputs |
| `Data\Output\<video-name>` | New analytics results and job manifest |
| `config\analytics` | One `.otflow` or `.otconfig` per fixed camera view |
| `config\otvision` | Optional OTVision threshold configurations |
| `models` | Optional validated custom YOLO weights |

The controller refuses paths outside `Data` and `config\analytics`. It never
deletes source files. Without `-Force`, OTVision is instructed not to overwrite
existing detections or tracks.

## 3. Install prerequisites on Windows

Your computer needs:

- Windows 10/11 with WSL 2 virtualization enabled.
- Docker Desktop using the WSL 2 engine.
- A current NVIDIA Windows driver for GPU mode.
- At least 16 GB system RAM recommended; allow Docker adequate memory and disk.

Docker and FFmpeg do not need to be separately installed inside Windows for
processing: FFmpeg is included in the OTVision image. Docker Desktop itself is
mandatory.

After installing Docker Desktop, enable **Use the WSL 2 based engine** and, if
shown, WSL integration. Restart PowerShell and run:

```powershell
cd "C:\Users\Ehsani\Github repos\Traffic_Detection"
.\traffic.ps1 preflight -Mode gpu
```

If GPU passthrough is unavailable, use `-Mode cpu`. CPU detection works but may
be substantially slower.

## 4. Build the pinned applications

GPU build:

```powershell
.\traffic.ps1 build -Mode gpu
```

CPU build:

```powershell
.\traffic.ps1 build -Mode cpu
```

The first build downloads Python, the pinned OpenTrafficCam releases,
dependencies, and the default `yolov8s.pt` weights. It can take a while and
requires internet access. Subsequent jobs reuse the images.

Versions are defined in `.env` or use these defaults:

```text
OTVision v0.7.2
OTAnalytics v0.7.4
uv 0.9.18
```

To customize versions, copy `.env.example` to `.env`, edit it, and rebuild.
Do not upgrade versions in the middle of a survey without regression testing.

## 5. One-time setup for every camera view

OTAnalytics cannot know which lanes and movements you want to count. Create a
configuration once for each camera position:

1. Download and run the matching OTAnalytics Windows release from
   `https://github.com/OpenTrafficCam/OTAnalytics/releases`.
2. Load a representative `.ottrk` and the corresponding MP4. Your existing
   `Data\Download` directory already contains a matching pair that can be used.
3. Draw sections at the desired virtual counting lines.
4. Define each from-to flow, assign clear flow names, and select road-user
   classes.
5. Visualize tracks and verify that valid movements cross both sections in the
   expected order.
6. Export an `.otflow` or `.otconfig` file.
7. Copy it to `config\analytics`, for example:

   ```text
   config\analytics\blabla.otflow
   ```

Use a new version whenever the camera moves, rotates, zooms, changes resolution,
or its field of view changes. Never choose a configuration solely because the
intersection name looks similar.

The existing CSV files describe earlier results but do not contain the complete
section geometry, so they cannot safely reconstruct the missing `.otflow`.

## 6. Prepare MP4 input

Place input under `Data`, normally `Data\Download`. OTVision requires the start
timestamp somewhere in the filename:

```text
YYYY-MM-DD_HH-MM-SS
```

Valid example:

```text
camera_north_2026-07-14_08-00-00.mp4
```

The included sample filename already satisfies this rule. Use a dummy timestamp
only if real time is irrelevant. Consecutive-video linking requires correct
timestamps.

## 7. Run the entire pipeline

```powershell
.\traffic.ps1 run `
  -InputFile "Download\camera_north_2026-07-14_08-00-00.mp4" `
  -AnalysisConfig "obermayer-camera-v1.otflow" `
  -Mode gpu `
  -CountIntervals 5,15,60 `
  -Processes 4
```

Use `-Force` only when you intentionally want OTVision to replace matching
`.otdet` and `.ottrk` files:

```powershell
.\traffic.ps1 run ... -Force
```

## 8. Run individual stages

Only detect and track an MP4:

```powershell
.\traffic.ps1 vision `
  -InputFile "Download\camera_north_2026-07-14_08-00-00.mp4" `
  -Mode gpu
```

Analyze an existing `.ottrk` without rerunning detection:

```powershell
.\traffic.ps1 analytics `
  -TrackFile "Download\Standard_SCUCPX_2024-10-08_0000.009_2024-10-08_08-00-02.ottrk" `
  -AnalysisConfig "obermayer-camera-v1.otflow" `
  -CountIntervals 15
```

Use custom weights stored in `models`:

```powershell
.\traffic.ps1 vision `
  -InputFile "Download\camera_north_2026-07-14_08-00-00.mp4" `
  -Weights "/models/my-validated-model.pt"
```

## 9. Results

Results are written to:

```text
Data\Output\<track-base-name>\
```

Depending on OTAnalytics configuration and version, outputs can include event
lists, interval counts, road-user assignments, track exports, track statistics,
CSV files, and XLSX files. `job-manifest.json` records the track, analysis
configuration, intervals, process count, and completion time.

Keep `.otdet`, `.ottrk`, the analysis configuration, model/version information,
and outputs together for auditability.

## 10. Accuracy validation

Container completion does not prove count accuracy. Before production:

1. Manually count several representative 15-minute windows.
2. Include daylight, darkness, glare, rain, congestion, and occlusion where
   relevant.
3. Compare each flow and class separately—not only the total count.
4. Review missed, duplicated, fragmented, and misclassified tracks.
5. Record acceptance thresholds before tuning parameters.

Only consider custom training after this comparison. Common triggers are
systematic bicycle/motorcycle misses, unusual vehicle classes, distant small
objects, or domain-specific night/weather conditions.

## 11. Troubleshooting

### `Docker is not installed`

Install Docker Desktop, enable its WSL 2 engine, start Docker Desktop, and reopen
PowerShell.

### GPU service cannot start

Check `nvidia-smi`, update the NVIDIA Windows driver, and confirm Docker Desktop
uses WSL 2. Use `-Mode cpu` to separate GPU configuration problems from pipeline
problems.

### Filename timestamp error

Rename the MP4 so it contains `YYYY-MM-DD_HH-MM-SS` without changing its file
extension.

### Expected `.otdet` or `.ottrk` is missing

Read the preceding container output. Common causes include unsupported video
codec, corrupt input, insufficient disk space, model download failure, or an
existing output combined with no-overwrite mode.

### Analytics asks for a configuration

Create and validate `.otflow`/`.otconfig` in the desktop GUI as described in
section 5. A trajectory file alone does not define flows.

### Counts look plausible but disagree with manual counts

Inspect section placement and track continuity first. Do not immediately train
a new detector: wrong flow geometry or tracking thresholds can produce count
errors even when detection is good.

## 12. Privacy and licensing

Traffic footage can contain faces and license plates. Restrict access, encrypt
transfers and storage as appropriate, minimize retention, and document deletion
rules. Obtain project-specific data-protection advice for the relevant country.

OpenTrafficCam components are GPL-3.0. The included Ultralytics software and
weights have additional AGPL/commercial licensing implications. Obtain legal
review before closed-source internal, SaaS, customer-facing, or commercial use.

Do not publish source videos merely because application source code is open.
Software licensing and personal-data obligations are separate issues.
