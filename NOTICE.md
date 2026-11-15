# 来源、许可与不包含的内容

## 本仓库的许可

- `docs/`、`scripts/`、`patches/android-switch/`：MIT（见 `LICENSE`）
- `patches/dipper-xnu/`、`patches/mi8-dualboot-lab/` 下的文件是对上游的修改，
  沿用各自上游许可证（见下）

## 上游项目

| 项目 | 用途 | 许可 |
| --- | --- | --- |
| [dipper-xnu](https://github.com/youzjuzi/dipper-xnu) | XNU/驱动/用户空间移植、xnuloader、UEFI 平台构建 | 见其仓库（GPL 系与 Apple 许可证混合） |
| [mi8-dualboot-lab](https://github.com/Hercules-Zhaoziyi/mi8-dualboot-lab) | 双启动菜单（SimpleInit 皮肤）、合成工具、shim 适配 | MIT / LGPL-3.0-or-later（见其 `LICENSES/`） |
| [edk2-sdm845](https://github.com/edk2-porting/edk2-sdm845) | UEFI 平台（Qualcomm SDM845） | BSD-2-Clause-Patent |
| [SimpleInit](https://github.com/BigfootACA/simple-init) | 引导管理器与图形菜单宿主 | LGPL-3.0-or-later |
| [Apple XNU](https://github.com/apple-oss-distributions/xnu) | 内核 | Apple Public Source License 2.0 |
| [LVGL](https://github.com/lvgl/lvgl) | 菜单图形库 | MIT |
| [NanoSVG](https://github.com/memononen/nanosvg) | SVG 渲染 | zlib |
| [FreeType](https://freetype.org/) | 字体渲染 | FreeType License / GPLv2 |

## 明确不包含的内容

为遵守许可证与法律，本仓库**不包含、也不要提交**：

- Apple 的任何系统镜像、IPSW、用户空间二进制、内核二进制、私有库
- 小米/高通的任何原厂固件、`boot.img`、`recovery.img`、分区备份
- 由上述材料派生出的合成镜像（`menu.img`、`android.img` 等 60+ MB 文件）
- 字体文件（Windows 系统字体及其子集）与生成的 `HerculesFont-*.ffs`
- 设备标识：序列号、IMEI、MAC 地址、分区镜像哈希以外的个人数据
- Wi-Fi 的 SSID 与密码

`.gitignore` 已阻止这些路径被误提交。

## 商标

Android、Google、小米、MIUI、Apple、iOS、快手、小红书等名称与图形属于各自权利人。
本仓库仅为技术记录，与上述公司无隶属关系。`patches/mi8-dualboot-lab/files/hercules-kuaishou.svg`
是为本机界面绘制的简化图标，不代表快手官方视觉资产。
