# 小米 8（dipper）iOS 16.5 双启动实践

> 在小米 8 上跑起 iOS 16.5，并让同一台手机在 **MIUI** 与 **iOS** 之间切换。
> 本仓库只包含**文档、脚本与补丁**；不含任何 Apple / 小米专有二进制、字库或设备备份。

---

## 成果

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| iOS 16.5 启动 | ✅ | XNU 8796.121.2 + 自备 iPhone10,3 用户空间 |
| GPU 硬件渲染 | ✅ | Adreno 630（Mesa），窗口动画、锁屏、控制中心正常 |
| 触摸 / 按键 | ✅ | `fts` 触摸屏、电源/音量键 |
| Wi-Fi | ✅ | WCN3990 + ath10k（LinuxKPI），WPA2 连接、DHCP、DNS |
| 扬声器音频 | ✅ | ADSP + TAS2557 功放，固件从手机 `modem` 分区读取 |
| 电池 / 手电筒 / 振动 | ✅ | 内核默认开启 |
| 数据保留 | ✅ | `var_store` 每 300 s 自动把 `/private/var` 写回 darwin 分区 |
| 双启动菜单 | ✅ | 图形菜单（LVGL），可选 Android / iOS，可进高级选项 |
| Android 启动 | ✅ | 角色对调方案：MIUI 在 `boot`，菜单在 `recovery` |
| 开机自动出菜单 | ⚠️ | 改为**音量上 + 电源**进入菜单（见 `docs/android.md` 的原因） |
| 蜂窝网络 | ❌ | 未实现 |
| iOS 滑动关机 | ❌ | 上游已知问题，关机会卡圈 |

---

## 整体架构

```
上电
  │
  ├─ 音量上 + 电源 ──────────────┐
  │                              ▼
  │                     recovery 分区 = 菜单镜像
  │                              │
  │                     shim → UEFI → SimpleInit 菜单
  │                              ├─ 选 Android → 重启 → boot 分区
  │                              └─ 选 iOS → FV GUID d82f808b → xnuloader → XNU
  │
  └─ 正常开机
        ▼
     boot 分区 = 强制 Android 镜像
        │
     shim 直接跳原厂 Android 内核 → MIUI
```

**关键点**：`boot` 与 `recovery` 各放一个「合成镜像」，两者都是：

```
原厂 Android 内核（供 shim 跳转）
  + UEFI 固件（7 MiB 固定卷）
  + iOS 载荷（XNUP：XNU 内核 + root.apfs + flashboot.apfs + 启动参数）
```

整个镜像以 legacy Android boot header（v0/v1 均可）封装，压缩后约 63 MiB，塞进 64 MiB 分区。

---

## 目录

```
docs/
  01-architecture.md        启动链、分区布局、内存布局
  02-build-ios.md           iOS 侧（dipper-xnu）构建与参数
  03-dualboot-menu.md       把 Hercules 菜单合并进自研固件
  04-boot-shim-and-payload.md  shim 补丁与载荷搬运（关键修复）
  05-android.md             Android 启动：BCB 方案为何失败、角色对调方案
  06-audio-and-persistence.md 音频与数据保留
  07-pitfalls.md            踩过的坑（按症状查）
  08-flash-and-rollback.md  刷写、校验、回退
scripts/                    可直接复用的构建/合成脚本
patches/                    需要应用到上游仓库的补丁
```

---

## 快速开始

前置条件：

- 小米 8（`dipper`），bootloader 已解锁
- 可用的 `fastboot`、TWRP
- WSL2 Ubuntu（本项目在 Ubuntu 26.04 上完成）
- 自备的 iOS 16.5 IPSW（iPhone10,3 / iPhone10,6）

大致步骤：

1. **备份**：`boot`、`recovery`、GPT、用户数据（见 `docs/08`）
2. **重分区**：在 GPT 里划出 24 GiB 的 `darwin` 分区（见 `docs/01`）
3. **构建 iOS 侧**：按 `docs/02` 构建 XNU、用户空间、loader、载荷
4. **合并菜单**：按 `docs/03` 把菜单编进 UEFI 固件
5. **打 shim 补丁**：按 `docs/04` 让 shim 把载荷搬到 loader 期望的地址
6. **合成镜像**：`scripts/compose-boot.sh`
7. **刷写**：`boot` = Android 镜像，`recovery` = 菜单镜像（`docs/05`）

---

## 许可与来源

本项目的工作建立在以下开源项目之上，详见 `NOTICE.md`：

- [dipper-xnu](https://github.com/youzjuzi/dipper-xnu)（XNU/驱动/用户空间移植）
- [mi8-dualboot-lab](https://github.com/Hercules-Zhaoziyi/mi8-dualboot-lab)（双启动菜单与合成方案）
- [edk2-sdm845](https://github.com/edk2-porting/edk2-sdm845)（UEFI 平台）
- [SimpleInit](https://github.com/BigfootACA/simple-init)（引导器/菜单宿主）
- Apple XNU（`Apple Public Source License`）

**本仓库不包含**：iOS IPSW、Apple 用户空间/内核二进制、小米固件或原厂 `boot.img`、字库文件、任何设备备份或分区镜像。

`docs/` 与 `scripts/` 采用 MIT；`patches/` 按其上游许可证（见各补丁文件头）。

---

## 免责声明

给手机刷非官方系统有变砖风险。本项目记录的步骤在**本人这一台**小米 8 上验证通过，不保证适用于其它机器、其它存储容量或其它 MIUI 版本。分区、LBA、GUID 等数值**切勿照抄**，务必按自己的设备实测。
