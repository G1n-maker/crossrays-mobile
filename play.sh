#!/bin/zsh
# 在 Mac 上跑 Cross Rays
#   结束方式：关掉游戏窗口，或在这个终端按 Ctrl-C
#   日志：logs_play.txt
cd "$(dirname "$0")"
exec env \
  DM_ROOT="$PWD/work/build" \
  DM_ROMFS="$PWD/work/build/extract/v720896/RomFS.img" \
  DM_SAVE="$PWD/work/build/run/save" \
  DM_TEMP="$PWD/work/build/run/temp" \
  DM_MSL_DIR="$PWD/work/build/shader/cache" \
  DM_FONT_DIR="$PWD/work/build/font" \
  DM_AOC_DIR="$PWD/work/build/aoc" \
  DM_NVN_SHMAP="$PWD/nxnative/dm/games/010055700CEA8000/shader_map.tsv" \
  DM_LANG=en-US \
  DM_WINDOW=1 \
  DM_AUDIO=1 \
  "$PWD/work/build/tools/dmhost" \
  "$PWD/work/build/patched_v720896" > "$PWD/logs_play.txt" 2>&1
