# 01 · 架构

## 1. 启动链

### 1.1 正常开机

```
PBL → XBL → ABL（骁龙引导程序）
              │ 读 boot 分区
              ▼
           shim（我们塞在 boot 镜像最前面的 256 字节）
              │
              ├─ 检测到「启动 Android」信号 → 跳原厂内核
              └─ 否则把 UEFI 固件复制到 0xCE000000 → 跳 UEFI
```

小米 8 的 `boot` 分区是标准 Android legacy boot 镜像（`ANDROID!` 头，页大小 4096）。本项目把 **shim 拼在解压后的内核最前面**，因此 ABL 解压后执行的第一条指令就是我们自己的代码。

### 1.2 UEFI 内部

```
UEFI（edk2-sdm845，7 MiB 固定卷）
  │
  ├─ SimpleInit（引导管理器，编入菜单皮肤）
  │     ├─ 菜单：Android / iOS / 高级选项
  │     ├─ 选 Android → 运行 AndroidSwitch（EFI 应用）→ 重启
  │     └─ 选 iOS      → 按 FV GUID 启动 xnuloader
  │
  └─ xnuloader（EFI 应用，FV GUID d82f808b-…）
        │ 从 0xF0000000 读 XNUP 载荷
        │ 读 kernel / ramdisk / boot(flashboot) / cmdline
        ▼
     XNU 内核启动
```

## 2. 分区布局

以下数值是**本机**实测结果，仅供对照，切勿照抄。

| 项目 | 值 |
| --- | --- |
| 逻辑扇区 | 4096 字节（GPT 用 4096，`sysfs` 的 start/size 用 512，需换算） |
| `darwin` 分区号 | #22 |
| `darwin` 起止 LBA | 23746560 – 30038010 |
| `darwin` 大小 | 6,291,451 扇区 ≈ 24 GiB |
| 分区类型 GUID | `7C3457EF-0000-11AA-AA11-00306543ECAC`（APFS） |
| 分区唯一 GUID | `14711D5A-BF9B-4906-9DB6-6CB753578665` |
| `boot` 分区 | 64 MiB（131072 × 512） |
| `recovery` 分区 | 64 MiB |
| `misc` 分区 | 1 MiB（存放 Android bootloader control block） |

`darwin` 分区里是 APFS 容器，iOS 的根卷与两个 cryptex 都在其中。

## 3. 内存布局（关键）

| 区域 | 地址 | 用途 |
| --- | --- | --- |
| Android 内核解压区 | 约 `0x80080000` | shim 就在这段的最前面 |
| UEFI 固件 | `0xCE000000` + 7 MiB | shim 复制过去后跳转 |
| iOS 载荷（XNUP） | `0xF0000000` | loader 从这里读内核与镜像 |
| 「启动 Android」magic | `0x17FE00000` | 原方案用它做信号（**不可靠**，见 `05`） |

`XNUP` 载荷最大 64 MiB（`PAYLOAD_MAX_SIZE 0x04000000`）。

## 4. 固件卷的两条硬约束

1. **FD 固定 7 MiB**（`configs/sdm845.conf` 的 `FD_SIZE=0x00700000`）。菜单版 `SimpleInitMain.efi` 有 8.6 MB，靠 LZMA 压缩才装得下，余量很小。
2. **载荷全部塞进 boot 镜像**。合成后 63 MiB，接近 64 MiB 上限；不能再加东西。

## 5. 启动参数

loader 解析的 XNUP 条目：

| 条目名 | 作用 |
| --- | --- |
| `kernel` | Mach-O 内核 |
| `ramdisk` | `root.apfs`（根卷，`/dev/md0` 或 `md1`） |
| `boot` | `flashboot.apfs`（boot 卷，放常驻区）——**本项目新增**，见 `04` |
| `cmdline` | 内核启动参数 |
| `usb` | 常驻等 USB 命令（调试用，合成镜像里必须去掉） |
| `physbase` / `rdres` / `checkpoint` / `timerprobe` / `idprobe` | 调试/测试 |

本机使用的 `cmdline`：

```
epoch=<时间戳> bootcpu=7 cpus=7 ufs=2 root_apfs=ufs_darwin \
wifi_mac=<MAC> \
ufs_write=1 var_store=1 var_save_ms=120000
```

- 不写 `audio=0` 就是开启音频（内核默认）
- `ufs_write=1` 允许内核写 darwin 分区
- `var_store=1` 打开数据卷保存
- `var_save_ms=120000` 运行结束时的保存预算（2 分钟）
- **不要**写 `loader_return_after=…`：合成工具刻意拒绝，会破坏双启动语义
