# 07 · 踩坑总表（按症状查）

## 构建主机（WSL / edk2）

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| `mig did not build` / `C compiler cannot create executables` / `ld: unknown option: -plugin` | **Theos 的 `ld` 进了 `PATH`**，污染所有主机构建（mig、EDK2 主机工具、apfs-tool 全都中招） | 构建主机工具时用干净 PATH：`PATH=/usr/lib/llvm-21/bin:/usr/local/bin:/usr/bin:/bin` |
| `llvm-ar: not found` | edk2 的 CLANG38 需要不带版本号的 `llvm-ar` | `export PATH="/usr/lib/llvm-21/bin:$PATH"` |
| `llvm-nm: Cannot find option named 'just-symbols'` | 系统只有 `llvm-nm-21` | 做软链 `~/bin-llvm/llvm-nm -> /usr/bin/llvm-nm-21` |
| BaseTools 编译失败：`./brotli/c/common/constants.h: No such file` | edk2 的 `brotli` 子模块没拉 | `git -C Common/edk2 submodule update --init BaseTools/Source/C/BrotliCompress/brotli MdeModulePkg/Library/BrotliCustomDecompressLib/brotli` |
| DSC 报 `LinuxSimpleMassStorage.inf is not found` | 缺 `Platform/EFI_Binaries` 子模块 | `git submodule update --init Platform/EFI_Binaries GPLDrivers/Library/SimpleInit` |
| DSC 报 `CryptoPkg/CryptoPkg.dec(25): Library/OpensslLib/openssl/include is not found` | 缺 OpenSSL 子模块 | `git -C Common/edk2 submodule update --init --jobs 4` |
| `prepare_sources.py` 报 `Existing dependency has changes` | 它用 `--no-checkout` 克隆后立刻检查工作区，把未检出误判为有改动 | 手动 `git checkout --detach <commit>` + 子模块 |
| 构建极慢、卡在 `git submodule update --recursive` | 递归去拉 OpenSSL 等无关子模块 | 只 init 需要的：`Common/edk2`、`Common/edk2-platforms`、`Platform/EFI_Binaries`、`GPLDrivers/Library/SimpleInit` |

## 网络

| 症状 | 解决 |
| --- | --- |
| `github.com` 直连超时 / `WININET_E_TIMEOUT` | 用镜像：`git config --global --add url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"` |
| 代理报 `Recv failure: Connection reset by peer` | 轮换 `ghfast.top` / `gh-proxy.com`，并 `git config --global http.version HTTP/1.1` |
| 推送自己的仓库失败 | 之前的 `insteadOf` 会把 `github.com` 改写成镜像，推送前先删掉这些规则 |

## 固件（UEFI）

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| `GenFv: ERROR 2000: the 86th file and 87th file have the same file GUID` | 同一个 GUID 既用 `INF` 引入又与 `FILE APPLICATION` 重复（`Reboot2PayloadApp.inf` 的 `FILE_GUID` 就是 `801a189c-…`） | 二选一，只保留 `INF` |
| `-Werror,-Wunused-function: 'hercules_flex_group'` | 改页脚时把所有调用点删掉了 | 保留一处调用，或加 `__attribute__((unused))` |
| 固件卷装不下菜单 | FD 固定 7 MiB，而 `SimpleInitMain.efi` 有 8.6 MB | 依赖 LZMA 压缩；别再往固件里加东西 |
| `loader.efi` 缺失却构建成功 | `XnuLoaderPkg/Binary/loader.efi` 不存在时 GenFds 会静默跳过 | 每次构建前 `build-loader-uefi.sh` 并 `cp loader.efi XnuLoaderPkg/Binary/` |

## 菜单

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| 屏幕是 `live NN s` 文本，没有图形菜单 | 见下四条 | 逐条排查 |
| ↳ SimpleInit 没读配置 | `confd` 只从**已挂载卷**读 `\simpleinit.static.uefi.cfg`，固件卷文件不算 | 在 `uefimain.c` 里**代码注入** confd 键值（`docs/03` 第 5 节） |
| ↳ 菜单函数提前 `return -1` | 帧缓冲 < 320×480、缺 config、背景图不是 1080×2248、字库加载失败 | 按 `docs/03` 第 6 节顺序排查 |
| ↳ 字库缺失 | 只显示 `Local UI font pack required` | 本机生成 RAW FFS 并加进 FDF |
| ↳ **loader 抢了启动流程** | `XnuLoaderDxe` 把自己插到 BootOrder 第一位 | 改成删除自己的 Boot#### 变量（`docs/04` 第 4 节） |
| 改了菜单文字后出现空白方块 | 字体子集是按源码字符扫出来的，新字没有字形 | 重新生成字库包 |
| 改了页脚后构建报 unused function | `-Werror` | 保留调用点 |

## iOS 启动

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| 屏幕刷 `live NN s` | loader 在等 `0xF0000000` 的 XNUP 载荷，shim 没搬 | 给 shim 加载荷搬运（`docs/04` 第 2 节） |
| `Panicked task …: pid 1: init` | 缺 boot 卷（`flashboot.apfs`），`/sbin/launchd` 找不到 | 给 loader 加 `boot` 条目（`docs/04` 第 3 节） |
| 内核日志里出现 `audio: …` 后 `= END OF LOG =` | 误判：其实是 `init` panic | 同上 |
| 合成时报 `Only legacy header version zero is supported` | 原厂 boot 是 header v1 | 放宽断言为 `in (0,1)`（`docs/04` 第 5 节） |
| 合成时报 `FileNotFoundError: libdeflate-gzip` | 缺压缩工具 | `sudo apt install libdeflate-tools` |
| 合成拒绝载荷 | 载荷里有 `loader_return_after` | 用不含它的载荷 |
| 汇编 shim 报 `no such instruction: movk` | 用了主机 `gcc` | 改用 `aarch64-linux-gnu-gcc` |
| 回读校验「不一致」 | 候选镜像 63 MiB，分区 64 MiB，回读含尾部填充 | 比对**前 N 字节**，并确认尾部全零 |

## Android

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| 选 Android 后重启又回菜单 | `0x17FE00000` 的 magic 没在热重启后保留 | 见 `docs/05`，改用角色对调 |
| 一直进 MIUI 回不到菜单 | 写了 BCB `boot-recovery`，但 ABL 不清指令 | `fastboot erase misc`，改用角色对调 |
| 想验证 Android 交接是否正常 | — | 把 shim 改成无条件跳 Android（`b _ClearFlags`），能进 MIUI 就说明交接没问题 |

## 数据保留

| 症状 | 原因 | 解决 |
| --- | --- | --- |
| 重启后改动全丢 | 默认只在「运行结束」保存，而双启动下运行永不结束 | `var_store watch 300` + `ufs_write=1 var_store=1` |
| 保存时界面卡几秒 | 每次写约 100 MB 到闪存 | 正常，可把间隔调大 |

## 环境/工具

| 症状 | 解决 |
| --- | --- |
| WSL 里写 `/mnt/f` 被沙箱拒绝 | 用 `wsl.exe -d Ubuntu-26.04 -- bash <脚本>` 并在调用时申请更高权限 |
| Windows PowerShell 里 `adb shell "…|…"` 行为异常 | 把逻辑写成 `.sh`，`adb push` 后 `adb shell sh /path` |
| 批处理文件出现 `__X]` 乱码 | 存成 GBK + CRLF，或改用 PowerShell |
