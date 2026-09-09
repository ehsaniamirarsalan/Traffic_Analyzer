# Setting up this project on a new machine (native, no Docker)

This describes a from-scratch install of the **native Windows path**
(`traffic-native.ps1`) on a machine that does not have Docker. It covers every
application involved, what has to be installed system-wide vs. what travels
with the project folder, and exactly which files/folders to copy.

## 1. Apps/components in the pipeline

| # | Component | What it is | Where it lives |
|---|---|---|---|
| 1 | **OTVision** | Detects + tracks road users in MP4 video (YOLOv8 on GPU) | `native/OTVision` (vendored, own `.venv`) |
| 2 | **OTAnalytics** | Turns tracks into counted events (CSV/XLSX) via hand-drawn `.otflow`/`.otconfig` sections; also has a desktop GUI for authoring those configs | `native/OTAnalytics` (vendored, own `.venv`) |
| 3 | **traffic-native.ps1** | Orchestrator: validates inputs, wires up each `.venv` without activating it, runs the two apps in sequence, writes `job-manifest.json` | repo root |
| 4 | **uv** | Resolves/installs a managed Python 3.12 and builds the two `.venv`s | `.tools/uv` (vendored copy) or a global install |
| 5 | **YOLOv8s weights** | Pretrained detector model used by OTVision | `models/yolov8s.pt` |
| 6 | **NVIDIA driver + GPU** | Hardware backend for PyTorch/CUDA | machine-level, not project files |

`traffic.ps1` + `compose.yaml` + `docker/*` are the Docker path — irrelevant
if Docker isn't available on the new machine; skip them.

## 2. System-level dependencies (install on the new machine itself)

### 2a. What you actually have to install by hand

| App | Required? | Why | Get it from |
|---|---|---|---|
| **NVIDIA GPU driver** | Yes | Everything downstream (`torch.cuda`, TensorRT) needs a working driver; `preflight` calls `nvidia-smi` and hard-fails without it | nvidia.com — regular Game Ready/Studio driver is fine, no separate "CUDA driver" package needed |
| **PowerShell** | Yes, but already built into Windows | Both controllers are `.ps1` scripts | ships with Windows |
| **Internet access** (one-time) | Yes | The install step downloads ~2–3 GB of PyTorch/CUDA/TensorRT wheels plus the rest of each app's dependencies | — |
| **`uv`** | Yes, one way or another | Builds/manages the Python 3.12 venvs | either copy `.tools/uv` from this machine (nothing to install), or run `irm https://astral.sh/uv/install.ps1 \| iex` in PowerShell on the new machine |

That's the whole manual-install list. Specifically, you do **NOT** need to
separately install:

- **Python** — no system/standalone Python installer needed. `uv` downloads
  and manages its own Python 3.12 build the first time it's needed
  (`uv python install 3.12`, or automatically during `uv sync`/`uv pip
  install`). `traffic-native.ps1` never looks for Python on `PATH`.
- **CUDA Toolkit / `nvcc`** — not needed. `torch==2.7.1+cu128` and the
  `tensorrt`/`tensorrt-cu12-*` packages (OTVision's `inference_cuda` extra)
  are all prebuilt wheels that bundle their own CUDA 12.8 runtime libraries.
- **cuDNN** — bundled inside the same wheels, same reasoning.
- **FFmpeg** — not needed as a separate system install. Video I/O goes
  through `av` (PyAV, statically-linked ffmpeg) and
  `opencv-python-headless` (also bundled). `moviepy`'s `imageio-ffmpeg`
  dependency will transparently download its own small ffmpeg binary into
  its package cache on first use if it ever needs one — that's automatic,
  not a manual install.
- **Visual Studio / Build Tools / a C++ compiler** — not needed. Every
  dependency pinned in `native/OTVision/pyproject.toml` and
  `native/OTAnalytics/pyproject.toml` ships as a prebuilt Windows wheel, so
  nothing gets compiled locally.
- **Git** — not needed; you're copying the vendored source trees directly,
  not cloning them.

The one edge case worth knowing about: prebuilt Windows wheels for
PyTorch/OpenCV generally need the **Microsoft Visual C++ Redistributable**
(the runtime DLLs, not Build Tools). It's already present on virtually all
Windows 10/11 installs; only worth installing manually if `preflight`
fails on `import torch` with a missing-DLL error.

### 2b. What gets installed automatically as part of §4

Everything else — OTVision, OTAnalytics, PyTorch/torchvision, TensorRT,
Ultralytics, OpenCV, pandas, etc. — is pulled in by `uv`/`pip` when you run
each app's own installer script in §4. There's nothing to install for these
beyond running those two commands.

## 3. What to copy from this machine

Copy the whole project directory, **except the two `.venv` folders** — they
are large (multi-GB), contain a compiled CUDA build of PyTorch, and are
cheaper/safer to rebuild on the target machine than to copy byte-for-byte.

Copy:

```
Traffic_Detection/
├── CLAUDE.md
├── README.md
├── USER_MANUAL.md
├── NATIVE_USER_MANUAL.md
├── traffic-native.ps1
├── traffic.ps1                  (harmless to bring even though unused)
├── compose.yaml                 (harmless to bring even though unused)
├── scripts/                     (validate-project.ps1 etc.)
├── .tools/uv/                   (uv.exe, uvw.exe, uvx.exe — skip global uv install if you bring this)
├── models/
│   ├── yolov8s.pt                (required — the detector weights)
│   └── README.md
├── config/
│   ├── analytics/                (all .otflow/.otconfig files — camera-specific, hand-authored, irreplaceable)
│   └── otvision/
├── Data/
│   ├── Download/                 (source videos + any existing .otdet/.ottrk/reference tracks you want to keep)
│   └── Output/                   (optional — past results; not required for the pipeline to run)
├── native/OTVision/               (everything EXCEPT native/OTVision/.venv)
└── native/OTAnalytics/            (everything EXCEPT native/OTAnalytics/.venv)
```

Do **not** copy:

- `native/OTVision/.venv`
- `native/OTAnalytics/.venv`
- `native/OTVision/tests`/`native/OTAnalytics/tests` cache artifacts, logs
  (`native/OTAnalytics/logs`, `config/analytics/logs`) — safe to skip, not
  required for operation.

If disk space/bandwidth for the copy is no concern, copying the `.venv`
folders isn't dangerous either — but the paths are machine-specific in
places and Windows Defender/security scanning tends to be the slow part
regardless, so a clean rebuild (§4) is the more reliable option and is what
this project's own manual (`NATIVE_USER_MANUAL.md`) assumes.

## 4. Rebuilding the two `.venv`s on the new machine

From inside the copied project folder:

```powershell
cd native\OTVision
.\install_cuda.cmd
```

This runs `uv sync --extra inference_cuda --no-dev`, which creates
`native\OTVision\.venv` and installs OTVision plus `torch==2.7.1+cu128`,
`torchvision`, `ultralytics`, etc.

```powershell
cd ..\OTAnalytics
.\install.cmd
```

This creates `native\OTAnalytics\.venv` (plain `python -m venv` + `uv pip
install .`) with OTAnalytics's own dependencies (no GPU packages needed
here).

Both installers require Python 3.12 to be resolvable — either `uv python
install 3.12` once beforehand, or let `uv sync`/`uv pip install` pull the
managed interpreter automatically.

## 5. Verify

```powershell
cd ..\..
.\traffic-native.ps1 preflight
```

This checks `nvidia-smi`, imports `torch` inside the OTVision venv and
asserts `torch.cuda.is_available()`, and imports `OTAnalytics` inside its
venv — using `traffic-native.ps1`'s own env-juggling (`Invoke-NativePython`)
instead of venv activation, so no system Python or `Activate.ps1` is
involved.

If preflight passes, the workflow is identical to the original machine:

```powershell
.\traffic-native.ps1 gui
.\traffic-native.ps1 run -InputFile "Download\<name>.mp4" -AnalysisConfig "<camera>.otflow"
```

## 6. Summary checklist

- [ ] NVIDIA driver installed, `nvidia-smi` works
- [ ] Project folder copied (minus the two `.venv`s, per §3)
- [ ] `native\OTVision\install_cuda.cmd` run successfully
- [ ] `native\OTAnalytics\install.cmd` run successfully
- [ ] `models\yolov8s.pt` present
- [ ] `config\analytics\*.otflow`/`.otconfig` present (or plan to re-author
      via `.\traffic-native.ps1 gui` if camera views changed)
- [ ] `.\traffic-native.ps1 preflight` passes
