#!/usr/bin/env bash
# 02-merge-menu.sh — 把 Hercules 双启动菜单合并进自研 dipper 固件
#
# 前提：已用 mi8-dualboot-lab 的 build_ui_components.sh 生成 dist/ui，
#       并用 make_local_font_pack.py 在 local/fonts 生成字体。
#
# 用法：LAB=~/mi8-dualboot-lab DIPPER_XNU=~/dipper-xnu bash 02-merge-menu.sh
set -euo pipefail

DIPPER_XNU="${DIPPER_XNU:-$HOME/dipper-xnu}"
LAB="${LAB:-$HOME/mi8-dualboot-lab}"
EDK2="$DIPPER_XNU/work/edk2"
DEST="$EDK2/Platform/Xiaomi/sdm845/Hercules"
IOS_GUID="d82f808b-ecca-4bb8-8e9f-9b9bafc490f5"
ANDROID_GUID="801a189c-e4a4-4195-85c2-64c5450a15ee"

[ -f "$LAB/dist/ui/simpleinit.static.uefi.cfg" ] || {
  echo "缺少 $LAB/dist/ui/simpleinit.static.uefi.cfg —— 先跑 build_ui_components.sh + package_components.py" >&2
  exit 1
}
[ -f "$LAB/local/fonts/hercules-ui-regular.ttf" ] || {
  echo "缺少本机字库 —— 先跑 make_local_font_pack.py" >&2
  exit 1
}

echo "=== 1/4 复制菜单资源 ==="
mkdir -p "$DEST"
cp -f "$LAB/dist/ui/simpleinit.static.uefi.cfg" "$DEST/"
cp -f "$LAB/local/fonts/hercules-ui-regular.ttf" "$DEST/"
cp -f "$LAB/local/fonts/hercules-ui-bold.ttf" "$DEST/"
cp -f "$LAB/dist/ui/AndroidHandoff.efi" "$DEST/AndroidHandoff.efi" 2>/dev/null || true
ls -l "$DEST"

echo "=== 2/4 改 DSC（字体开关）==="
python3 - "$EDK2/Platform/Xiaomi/sdm845/dipper.dsc" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'HERCULES_EXTERNAL_UI_FONTS' not in s:
    s = s.replace('-DENABLE_SIMPLE_INIT -DENABLE_LINUX_SIMPLE_MASS_STORAGE',
                  '-DENABLE_SIMPLE_INIT -DENABLE_LINUX_SIMPLE_MASS_STORAGE -DHERCULES_EXTERNAL_UI_FONTS=1', 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('已加字库开关')
else:
    print('已有字库开关')
PY

echo "=== 3/4 改 FDF（配置 + 字库资源）==="
python3 - "$EDK2/Platform/Xiaomi/sdm845/dipper.fdf.inc" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if '4b0364cf' in s:
    print('FDF 已有菜单资源')
else:
    s = s.rstrip('\n') + '''

// ---- Hercules 双启动菜单 ----
FILE FREEFORM = 4b0364cf-1c5b-47aa-9073-d7b5039ce49b {
  SECTION RAW = Platform/Xiaomi/sdm845/Hercules/simpleinit.static.uefi.cfg
  SECTION UI = "simpleinit.static.uefi.cfg"
}
FILE FREEFORM = e71a7a5c-8196-4d48-b641-09d21a13bdf4 {
  SECTION RAW = Platform/Xiaomi/sdm845/Hercules/hercules-ui-regular.ttf
}
FILE FREEFORM = 30c1b010-8e7b-48a7-bd44-6978cf57d210 {
  SECTION RAW = Platform/Xiaomi/sdm845/Hercules/hercules-ui-bold.ttf
}
'''
    open(p, 'w', encoding='utf-8').write(s)
    print('已追加菜单资源')
PY

echo "=== 4/4 用菜单版 SimpleInit 构建固件 ==="
export SIMPLE_INIT="$LAB/source/simple-init"
export MI8_ROOT="$DIPPER_XNU"
export EDK2_ROOT="$EDK2/Common/edk2"
unset XNU_PAYLOAD
export PATH="/usr/lib/llvm-21/bin:$DIPPER_XNU/work/host-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
( cd "$EDK2" && bash build.sh -d dipper )

FD="$EDK2/workspace/Build/dipper/RELEASE_CLANG38/FV/SDM845_UEFI.fd"
ls -l "$FD"
[ "$(stat -c%s "$FD")" -eq 7340032 ] || { echo "FD 不是 7 MiB，检查 FD_SIZE" >&2; exit 1; }
echo "OK: $FD"
echo
echo "提醒：菜单能不能显示，取决于 SimpleInit 是否读到 boot.hercules_skin。"
echo "      本项目用 patches/mi8-dualboot-lab/simpleinit-confd-inject.patch 在代码里注入，见 docs/03。"
