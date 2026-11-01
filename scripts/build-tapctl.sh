#!/bin/bash
# ZIG=/path/to/zig scripts/build-tapctl.sh
set -euo pipefail
cd "$(dirname "$0")/.."
compiler="${ZIG:-$(command -v zig || true)}"
if [ -z "$compiler" ]; then
  echo '找不到 zig，请用 ZIG=/path/to/zig 指定。' >&2
  exit 1
fi
mkdir -p tools/build
"$compiler" cc -target arm-linux-musleabihf -static -O2 -Wall -Wextra -Werror \
  tools/tapctl.c -o tools/build/tapctl
file tools/build/tapctl
