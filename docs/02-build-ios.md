# 02 · iOS 侧构建（dipper-xnu）

## 1. 获取源码

```bash
git clone https://github.com/youzjuzi/dipper-xnu ~/dipper-xnu
```

国内直连 GitHub 常常失败，可以用镜像：

```bash
git config --global --add url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"
git config --global http.version HTTP/1.1
```

**注意**：镜像规则会影响 `git push`，推送自己的仓库前要临时去掉（见 `08`）。

## 2. 依赖准备

```bash
cd ~/dipper-xnu
python3 tools/prepare/prepare.py --prepare      # 拉固定版本源码并打补丁
python3 tools/prepare/prepare.py --iosw <IPSW>  # 从自备 IPSW 提取用户空间
```

常见的依赖坑见 `07-pitfalls.md`，尤其是：**Theos 的 `ld` 一旦进入 `PATH`，所有主机构建都会莫名失败**。

## 3. 构建顺序

```bash
# 1. 内核
bash tools/build/build-kernel.sh

# 2. 用户空间（生成 root.apfs / flashboot.apfs）
bash tools/build/build-userland.sh

# 3. loader（EFI 应用）
bash tools/build/build-loader-uefi.sh
cp work/hackios/xnuloader/loader.efi work/packages/XnuLoaderPkg/Binary/loader.efi

# 4. 载荷
python3 tools/build/build-payload.py --output work/runs/<新目录> \
  --wifi --persist --seconds 0
```

`build-payload.py` 会拒绝覆盖已存在的输出目录，每次用新的 `RUN_ID`。

## 4. 设备相关数值必须同步

三个地方必须与实际分区一致，改一处就要全部重建：

| 文件 | 字段 |
| --- | --- |
| `work/hackios/xnuloader/loader.c` | `BLOCK_DARWIN_FIRST` / `BLOCK_DARWIN_LAST` / `BLOCK_DARWIN_TYPE` / `BLOCK_DARWIN_UNIQ` |
| `work/hackios/xnu-src/xnu-8796.121.2/bsd/dev/redwood_ufs.c` | `UFS_DARWIN_FIRST` / `UFS_DARWIN_BLOCKS` |
| 分区工具 | 节点、GUID、逻辑扇区、保护区 |

本机实际值（4096 字节扇区）：

```c
BLOCK_DARWIN_FIRST 30038010ULL
BLOCK_DARWIN_LAST  23746560ULL   /* 注意上游写法是「尾部在前」 */
UFS_DARWIN_FIRST   23746560ULL
UFS_DARWIN_BLOCKS  6291451ULL
```

## 5. 构建产物

| 产物 | 大小 | 说明 |
| --- | --- | --- |
| `kernel.macho` | ~16 MB | XNU |
| `root.apfs` | ~11 MB | 根卷（含 `/fw` 固件） |
| `flashboot.apfs` | ~4 MB | boot 卷（含 `/sbin/launchd`） |
| `loader.efi` | ~71 KB | EFI 加载器 |
| `payload.bin` | ~26 MB | XNUP（kernel + ramdisk + cmdline） |

`root.apfs` 的 `/fw` 里要有：

- `network`（第一行 SSID，第二行密码）
- `firmware-5.bin`、`a630_*`（GPU）
- TAS2557 的 `tas2557_uCDSP_goer.bin`（42730 字节）
- 蓝牙 `crbtfw21.tlv`、`crnv21.bin`

`flashboot.apfs` 的 `/fw` 里要放功放与蓝牙固件（视构建脚本而定）。

## 6. Wi-Fi

`wifi=1` 这台机器**走不通**：`redwood_wifi.c` 无条件要求 `fw/wpss.mdt`（qca6750 固件），而小米 8 用的是 `wlanmdsp.mbn` + `bdwlan.bin`。

可用配置：

```
wifi_lx=2 wifi_station=1 wifi_quiet=0 wifi_mac=<MAC>
```

外加 `root.apfs` 的 `/fw/network` 写入 SSID 与密码。iOS 的「地区」要设为中国大陆，否则 5 GHz 信道受限。首次 DHCP 可能很慢（实测 ~325 秒），偶发 Fault Detected，属已知现象。
