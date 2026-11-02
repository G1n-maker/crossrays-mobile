#!/bin/zsh
# Wrapper: puts the locally installed toolchain on PATH, then runs nxnative's build script.
# Everything lives under this folder, so nothing was installed into /usr/local, /opt or Homebrew.
#
#   .tools/uv                  uv (fetched Python 3.12.16 into .venv)
#   .venv                      lz4, capstone 5.x, fonttools, nsz, backports.zstd
#   .tools/dotnet              .NET SDK 10 (nx_extract and the shader translator run on it)
#   .tools/xcodegen            XcodeGen 2.46.0 (the iOS project generator)
#   .tools/glslang/bin         glslangValidator (an OpenGL title's shaders)
#   .tools/bin/zstd            zstd 1.5.7
#
# Usage: ./run_nxnative.sh Game -k keys/prod.keys [options]
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
export DOTNET_ROOT="$ROOT/.tools/dotnet"
export PATH="$ROOT/.tools/uv:$ROOT/.tools/dotnet:$ROOT/.tools/xcodegen/bin:$ROOT/.tools/glslang/bin:$ROOT/.tools/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
exec "$ROOT/.venv/bin/python" "$ROOT/nxnative/scripts/build_ipa_from_nsp.py" "$@"
