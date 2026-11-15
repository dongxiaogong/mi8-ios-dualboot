#!/usr/bin/env bash
# 05-flash.sh — 刷写与回读校验（角色对调方案：boot=Android，recovery=菜单）
#
# 用法：
#   SERIAL=<SERIAL> ANDROID_IMG=~/out/android.img MENU_IMG=~/out/menu.img \
#   BACKUP_BOOT=~/boot-original.img BACKUP_RECOVERY=~/recovery-original.img \
#   bash 05-flash.sh
set -euo pipefail

SERIAL="${SERIAL:?需要设备序列号（fastboot devices 看到的那个）}"
ANDROID_IMG="${ANDROID_IMG:?需要 Android 镜像}"
MENU_IMG="${MENU_IMG:?需要菜单镜像}"
FB="fastboot -s $SERIAL"

echo "=== 0. 确认设备 ==="
$FB getvar product 2>&1 | head -2

echo "=== 1. 清掉可能残留的启动指令 ==="
$FB erase misc || echo "（erase misc 不支持时，进 TWRP 把 misc 前 2 KB 清零）"

echo "=== 2. 刷入 ==="
$FB flash boot     "$ANDROID_IMG"
$FB flash recovery "$MENU_IMG"

echo "=== 3. 回读校验（按有效长度比，尾部应为全零）==="
BOOT_DUMP="$(mktemp)"
$FB boot "${TWRP_IMG:?需要 TWRP 镜像路径}" || true
sleep 30
adb -s "$SERIAL" shell "dd if=/dev/block/by-name/boot of=/tmp/rb.img bs=1048576" >/dev/null 2>&1
adb -s "$SERIAL" pull /tmp/rb.img "$BOOT_DUMP" >/dev/null
python3 - "$ANDROID_IMG" "$BOOT_DUMP" <<'PY'
import sys
cand = open(sys.argv[1], 'rb').read()
back = open(sys.argv[2], 'rb').read()
assert back[:len(cand)] == cand, '有效内容不一致！'
assert set(back[len(cand):]) <= {0}, '尾部不是全零'
print('回读校验通过：', len(cand), '字节一致，尾部', len(back) - len(cand), '字节填充')
PY
rm -f "$BOOT_DUMP"

echo
echo "完成。正常开机 → MIUI；音量上 + 电源 → 菜单。"
echo "回退："
echo "  $FB flash boot     ${BACKUP_BOOT:-boot-original.img}"
echo "  $FB flash recovery ${BACKUP_RECOVERY:-recovery-original.img}"
echo "  $FB erase misc"
