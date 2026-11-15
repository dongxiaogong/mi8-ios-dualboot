#!/usr/bin/env bash
# 03-patch-shim.sh — 生成「带载荷搬运」的 BootShim，并汇编成 bin
#
# 上游的 BootShim.Dualboot.S 不会把 XNUP 载荷搬到 0xF0000000，
# 而 loader 固定从那里读，于是只会打印 "live NN s"。
#
# 用法：LAB=~/mi8-dualboot-lab bash 03-patch-shim.sh
set -euo pipefail

LAB="${LAB:-$HOME/mi8-dualboot-lab}"
SRC="$LAB/source/device-adapters/dipper/BootShim.Dualboot.S"
OUTDIR="${OUTDIR:-$LAB/local/build}"
OUT_S="$OUTDIR/BootShim.Dualboot.Payload.S"
OUT_BIN="$OUTDIR/BootShim.Dualboot.bin"

mkdir -p "$OUTDIR"
[ -f "$SRC" ] || { echo "缺少 $SRC" >&2; exit 1; }

python3 - "$SRC" "$OUT_S" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()

if '_PayloadLoop' in s:
    print('已经带载荷搬运')
    open(dst, 'w', encoding='utf-8').write(s)
    raise SystemExit(0)

old = "\tbl \t\t_CopyLoop\n\n_Entry:\n"
new = """\tbl \t\t_CopyLoop

\t/* x4 此时指向 FD 之后：可能跟着 XNUP 载荷，搬到 PAYLOAD_BASE */
\tldr\t\tw2, [x4]
\tmovz\tw3, #0x4E58
\tmovk\tw3, #0x5055, lsl #16
\tcmp\t\tw2, w3
\tb.ne\t_Entry
\tldr\t\tw6, [x4, #4]
\tadd\t\tx6, x6, #23
\tand\t\tx6, x6, #~15
\tmovz\tx5, #(PAYLOAD_BASE >> 16), lsl #16

_PayloadLoop:
\tldp\t\tx2, x3, [x4], #16
\tstp\t\tx2, x3, [x5], #16
\tsubs\tx6, x6, #16
\tb.ne\t_PayloadLoop

_Entry:
"""
if old not in s:
    raise SystemExit('未找到插入点，请检查 BootShim.Dualboot.S 的版本')
open(dst, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print('已插入载荷搬运')
PY

# 必须用交叉编译器；主机 gcc 会报 "no such instruction: movk"
aarch64-linux-gnu-gcc -c "$OUT_S" -o "$OUTDIR/shim.elf" \
  -DUEFI_BASE="${UEFI_BASE:-0xCE000000}" \
  -DUEFI_SIZE="${UEFI_SIZE:-0x00700000}" \
  -DPAYLOAD_BASE="${PAYLOAD_BASE:-0xF0000000}"
aarch64-linux-gnu-objcopy -O binary "$OUTDIR/shim.elf" "$OUT_BIN"

ls -l "$OUT_BIN"
echo "OK: $OUT_BIN"
