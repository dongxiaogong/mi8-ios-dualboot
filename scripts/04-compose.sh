#!/usr/bin/env bash
# 04-compose.sh — 合成双启动 boot 镜像（用 mi8-dualboot-lab 的工具 + v1 头适配）
#
# 输入：原厂 boot 备份、7 MiB UEFI 固件、带载荷搬运的 shim、主机版 kernelpatcher、XNUP 载荷
# 输出：约 63 MiB 的 legacy Android boot 镜像，可刷入 64 MiB 的 boot / recovery 分区
#
# 用法：
#   ORIG_BOOT=~/boot-original.img ORIG_SHA=<sha256> \
#   FD=.../SDM845_UEFI.fd SHIM=.../BootShim.Dualboot.bin \
#   PATCHER=.../kernelpatcher PAYLOAD=.../payload.bin OUT=.../menu.img \
#   bash 04-compose.sh
set -euo pipefail

LAB="${LAB:-$HOME/mi8-dualboot-lab}"
ORIG_BOOT="${ORIG_BOOT:?需要原厂 boot 备份}"
ORIG_SHA="${ORIG_SHA:?需要原厂 boot 的 sha256}"
FD="${FD:?需要 SDM845_UEFI.fd}"
SHIM="${SHIM:?需要 BootShim.Dualboot.bin}"
PATCHER="${PATCHER:?需要主机版 kernelpatcher}"
PAYLOAD="${PAYLOAD:?需要 payload.bin}"
OUT="${OUT:?需要输出路径}"
PART_BYTES="${PART_BYTES:-67108864}"

# 1. 工具必须是主机可执行的 kernelpatcher（仓库自带的那个是 aarch64）
if ! file "$PATCHER" | grep -q 'x86-64'; then
  echo "kernelpatcher 不是 x86-64，尝试用主机 gcc 编译"
  gcc -O2 -o "$PATCHER" "${EDK2:-$HOME/dipper-xnu/work/edk2}/tools/Installer/src/kernelpatcher.c"
fi

# 2. 复制合成工具并放宽 header 版本断言（原厂是 v1）
TOOL="$LAB/local/compose_v1.py"
cp -f "$LAB/tools/compose_dipper_boot.py" "$TOOL"
python3 - "$TOOL" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = "assert struct.unpack_from('<I',orig,40)[0]==0,'Only legacy header version zero is supported'"
new = "assert struct.unpack_from('<I',orig,40)[0] in (0,1),'Only legacy header versions 0/1 are supported'"
if old in s:
    s = s.replace(old, new, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('已放宽到 v0/v1')
elif new in s:
    print('已是 v0/v1')
else:
    raise SystemExit('未找到断言，检查工具版本')
PY

# 3. 合成（工具要求输出目录不存在，且位于仓库 local/ 下）
OUTDIR="$(dirname "$OUT")"
mkdir -p "$OUTDIR"
CAND="$LAB/local/candidate-$(date +%Y%m%d-%H%M%S)"
rm -rf "$CAND"

python3 "$TOOL" \
  --device dipper \
  --original-boot "$ORIG_BOOT" \
  --original-sha256 "$ORIG_SHA" \
  --firmware "$FD" \
  --shim "$SHIM" \
  --kernelpatcher "$PATCHER" \
  --payload "$PAYLOAD" \
  --boot-partition-bytes "$PART_BYTES" \
  --out "$CAND"

cp -f "$CAND/boot-local-candidate.img" "$OUT"
ls -lh "$OUT"
sha256sum "$OUT"
