# Local Linux build environment for LogChard.
# Same dep set as .github/workflows/release.yaml.
#
#   docker build -f tool/linux.Dockerfile -t logchard-linux-build .
#   docker run --rm -v %CD%:/app -w /app logchard-linux-build \
#     bash -c "flutter pub get && flutter build linux --release"
#
# Output lands in build/linux/x64/release/bundle/ on the host.

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git xz-utils unzip ca-certificates \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev liblzma-dev libstdc++-12-dev \
    && rm -rf /var/lib/apt/lists/*

# Flutter version comes from .fvmrc (single source of truth) via
# --build-arg in tool/package-linux.sh. Default kept in sync for
# direct `docker build` usage.
ARG FLUTTER_VERSION=3.47.5
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN git config --global --add safe.directory /opt/flutter \
    && flutter precache --linux \
    && flutter config --enable-linux-desktop

WORKDIR /app
