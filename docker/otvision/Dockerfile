FROM python:3.12-slim-bookworm

ARG OTVISION_VERSION=v0.7.2
ARG OTVISION_INFERENCE=inference_cpu
ARG UV_VERSION=0.9.18

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_NO_PROGRESS=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
        git \
        libglib2.0-0 \
        libgl1 \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir "uv==${UV_VERSION}"

WORKDIR /opt
RUN git clone --depth 1 --branch "${OTVISION_VERSION}" \
        https://github.com/OpenTrafficCam/OTVision.git OTVision

WORKDIR /opt/OTVision
RUN uv sync --frozen --no-dev --extra "${OTVISION_INFERENCE}" \
    && uv run --frozen python -c "from ultralytics import YOLO; YOLO('yolov8s.pt')"

LABEL org.opencontainers.image.source="https://github.com/OpenTrafficCam/OTVision" \
      org.opencontainers.image.version="${OTVISION_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-only"

CMD ["uv", "run", "--frozen", "python", "-c", "print('Use traffic.ps1 to run OTVision')"]
