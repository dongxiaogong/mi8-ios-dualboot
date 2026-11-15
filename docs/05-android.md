# 05 · Android 启动

这一节记录**两次失败**和**最终可用方案**，因为失败的两次都很有教育意义。

## 1. 方案 A：magic + 热重启（上游设计，本机不可用）

设计：

```
菜单选 Android
  → Reboot2PayloadApp 往 0x17FE00000 写 128 个半字 0x5241 ('AR')
  → WriteBackInvalidateDataCacheRange + EfiResetWarm
  → ABL 重新加载 boot → shim 扫描该地址
      ├─ 命中 → 清除 magic → 跳原厂内核
      └─ 未命中 → 复制 UEFI → 菜单（于是又回到菜单）
```

实测：**每次都回到菜单**，说明 magic 没在热重启后保留下来（可能被 ABL 覆盖）。

验证交接链路本身没问题的方法：把 shim 改成**无条件走 Android 分支**（`b _ClearFlags` 直接跳），刷进去 → MIUI 正常启动。
所以问题只在「信号」，内核跳转完全正常。

结论：`0x17FE00000` 在这台机器上不可靠，放弃。

## 2. 方案 B：写 misc 的 BCB（失败，ABL 不清指令）

Android bootloader 用 `misc` 分区里的 bootloader control block 决定本次启动目标：

```c
struct bootloader_message {   /* 2048 字节 */
    char command[32];         /* "boot-recovery" */
    char status[32];
    char recovery[768];
    char stage[32];
    char reserved[1184];
};
```

做法：菜单里 Android 入口换成一个 EFI 程序（`AndroidSwitch`），按 GPT 分区名找到 `misc`，用 `EFI_BLOCK_IO` 写 `boot-recovery`，然后冷重启。ABL 会改启动 `recovery` 分区（我们把强制 Android 镜像放那里）。

**为什么失败**：AOSP 的 bootloader 在进入 recovery 后会清除 command，但我们的「recovery」其实是普通 Android 启动，没有人去清 BCB。于是每次开机都按指令进 recovery → 永远进 MIUI，回不到菜单。

（补救：进 TWRP 用 `dd` 把 `misc` 前 2 KB 清零，或 `fastboot erase misc`。）

## 3. 方案 C：角色对调（最终采用）

不再需要任何「信号」：

| 分区 | 内容 | 行为 |
| --- | --- | --- |
| `boot` | 强制 Android 的合成镜像 | 正常开机 → MIUI（秒开，和原厂一样） |
| `recovery` | 菜单合成镜像 | **音量上 + 电源** → 菜单 |

菜单里的 Android 入口退化成「只重启」：

```c
gRT->ResetSystem(EfiResetCold, EFI_SUCCESS, 0, NULL);
CpuDeadLoop();
```

重启后 ABL 读 `boot` → shim 无条件跳 Android → MIUI。

iOS 入口不变：菜单按 FV GUID `d82f808b-…` 启动 loader。

### 为什么接受「菜单要按键进入」

前两个方案都依赖**外部组件按我们的假设行事**（内存存活 / ABL 清指令），都不可靠。
角色对调只依赖一件事：**两个分区各放一个镜像**，而这是 bootloader 本来就保证的。

代价是开机不再自动出菜单。换来的是：

- Android 启动速度与原厂一致
- 不会因为某个信号丢失而困在菜单或困在 Android
- 两个系统都能随时进入

### 刷写

```bash
fastboot erase misc                      # 清掉可能残留的 BCB
fastboot flash boot    android.img       # 强制 Android 的合成镜像
fastboot flash recovery menu.img         # 菜单合成镜像
fastboot reboot
```

> 覆盖 `recovery` 会丢掉原厂 recovery。本机一直用 `fastboot boot twrp.img` 临时启动 TWRP，不依赖分区里的 recovery；要恢复可从官方 fastboot 包刷回。

## 4. 如果以后想恢复「开机自动出菜单」

可行但都更麻烦，记录在这里：

1. **让 ABL 认的一次性指令**：把 recovery 换成真正的 AOSP recovery（它会清 BCB），但那样它又不会启动 Android。
2. **在 Android 侧清 BCB**：给 MIUI 的 ramdisk 加一个开机脚本（需要重新打包 ramdisk，破坏 OTA）。
3. **UEFI 直接跳 Android 内核**：shim 把 ABL 传进来的 dtb 指针和内核入口存到固定地址，菜单退出引导服务后自己跳过去。工作量最大，但完全不依赖信号。
4. **把菜单做成 Android 的一个启动阶段**：不现实。

## 5. AndroidSwitch 源码

见 `patches/android-switch/AndroidSwitch.c`（完整文件）。它的两种形态：

- 方案 B：写 BCB + 冷重启（已弃用，保留作参考）
- 方案 C：只重启（当前使用）

`FILE_GUID` 用 `801a189c-e4a4-4195-85c2-64c5450a15ee`，与菜单配置里 `android` 入口的 `efi_fv_guid` 一致，因此换实现不用改菜单配置。

编译要点：`[Protocols]` 里要声明 `gEfiBlockIoProtocolGuid` 与 `gEfiPartitionInfoProtocolGuid`；后者定义在 `MdePkg/Include/Protocol/PartitionInfo.h`，GUID 为 `8cf2f62c-bc9b-4821-808d-ec9ec421a1a0`。
