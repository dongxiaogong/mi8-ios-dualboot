#!/usr/bin/env bash
# 01-build-ios.sh — 构建 iOS 侧全套产物
#
# 依赖：本机已跑过 dipper-xnu 的 prepare（含自备 IPSW）
# 用法：DIPPER_XNU=~/dipper-xnu bash 01-build-ios.sh
set -euo pipefail

DIPPER_XNU="${DIPPER_XNU:-$HOME/dipper-xnu}"
cd "$DIPPER_XNU"

# Theos 的 ld 会污染主机构建，这里显式去掉
export PATH="/usr/lib/llvm-21/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "=== 1/4 内核 ==="
bash tools/build/build-kernel.sh

echo "=== 2/4 用户空间 ==="
bash tools/build/build-userland.sh

echo "=== 3/4 loader ==="
bash tools/build/build-loader-uefi.sh
mkdir -p work/packages/XnuLoaderPkg/Binary
cp -f work/hackios/xnuloader/loader.efi work/packages/XnuLoaderPkg/Binary/loader.efi
ls -l work/packages/XnuLoaderPkg/Binary/loader.efi

echo "=== 4/4 载荷 ==="
# build-payload.py 拒绝覆盖旧目录，每次换名字
RUN="work/runs/$(date +%Y%m%d-%H%M)"
python3 tools/build/build-payload.py --output "$RUN" --wifi --persist --seconds 0
echo
echo "产物在 $RUN ："
ls -lh "$RUN"
cat "$RUN/cmdline.txt"
