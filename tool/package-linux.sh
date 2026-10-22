#!/bin/bash
# LogChard Linux packaging — builds + tars entirely inside Docker so
# plugin registrants are fresh and exec bits survive. Run from repo root:
#
#   bash tool/package-linux.sh
#
# Output: build/log-chard-linux-x64.tar.gz
#
# Contents: log_chard app, logchard CLI, logchard-mcp MCP server,
# flutter runtime (lib/, data/), icon, .desktop entry, install.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=logchard-linux-build
TAR=build/log-chard-linux-x64.tar.gz

# Git Bash rewrites unix-looking args to Windows paths; stop it.
export MSYS_NO_PATHCONV=1

docker build -f tool/linux.Dockerfile -t "$IMAGE" .

# Stale artifacts from earlier mounts/broken pub states poison the
# plugin registrant — wipe everything that isn't the final tarball.
rm -rf build/linux linux/flutter/ephemeral \
       .flutter-plugins .flutter-plugins-dependencies
rm -f "$TAR"

# Docker on Windows runs as root — generated files land root-owned on the
# host mount. Harmless for builds; rebuilds re-wipe anyway.
docker run --rm -v "$PWD:/app" -w /app "$IMAGE" bash -euxo pipefail -c '
  flutter pub get
  flutter build linux --release
  dart compile exe bin/logchard.dart   -o build/linux/x64/release/bundle/logchard
  dart compile exe bin/mcp_server.dart -o build/linux/x64/release/bundle/logchard-mcp

  rm -rf /tmp/pkg && mkdir /tmp/pkg
  cp -a build/linux/x64/release/bundle/. /tmp/pkg/
  cp assets/icon-256.png tool/log-chard.desktop tool/install.sh /tmp/pkg/
  chmod 755 /tmp/pkg/log_chard /tmp/pkg/logchard /tmp/pkg/logchard-mcp /tmp/pkg/install.sh
  chmod 644 /tmp/pkg/icon-256.png /tmp/pkg/log-chard.desktop
  tar -czf /app/build/log-chard-linux-x64.tar.gz -C /tmp/pkg .
'

echo "==> $TAR"
tar -tzvf "$TAR" | grep -vE '\./lib/|\./data/'
