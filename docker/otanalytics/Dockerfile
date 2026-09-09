FROM python:3.12-slim-bookworm

ARG OTANALYTICS_VERSION=v0.7.4
ARG UV_VERSION=0.9.18

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_NO_PROGRESS=1 \
    MPLBACKEND=Agg

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        libglib2.0-0 \
        libgl1 \
        libgomp1 \
        tk \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir "uv==${UV_VERSION}"

WORKDIR /opt
RUN git clone --depth 1 --branch "${OTANALYTICS_VERSION}" \
        https://github.com/OpenTrafficCam/OTAnalytics.git OTAnalytics

WORKDIR /opt/OTAnalytics
RUN uv sync --frozen --no-dev

LABEL org.opencontainers.image.source="https://github.com/OpenTrafficCam/OTAnalytics" \
      org.opencontainers.image.version="${OTANALYTICS_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0-only"

CMD ["uv", "run", "--frozen", "python", "-m", "OTAnalytics", "--help"]
