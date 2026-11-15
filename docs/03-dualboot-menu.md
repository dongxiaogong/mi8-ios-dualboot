# 03 · 把双启动菜单合并进自研固件

菜单来自 [mi8-dualboot-lab](https://github.com/Hercules-Zhaoziyi/mi8-dualboot-lab)。它不是独立程序，而是 **SimpleInit 的一套皮肤**：`boot.hercules_skin = true` 时由 SimpleInit 自己绘制。

## 1. 准备

```bash
git clone --depth 1 https://github.com/Hercules-Zhaoziyi/mi8-dualboot-lab ~/mi8-dualboot-lab
cd ~/mi8-dualboot-lab
python3 tools/prepare_sources.py --dest local/edk2-sdm845
```

> `prepare_sources.py` 用 `--no-checkout` 克隆后立刻检查工作区，会把「未检出」误判成「有改动」而退出。
> 手动做它该做的事即可：

```bash
cd local/edk2-sdm845
git checkout --detach <UPSTREAM_SOURCES.json 里的 edk2_port.commit>
git submodule update --init Common/edk2 Common/edk2-platforms
git -C Common/edk2 submodule update --init --jobs 4   # BaseTools 需要 brotli/openssl
cd ../..
```

还需要 `Platform/EFI_Binaries`、`GPLDrivers/Library/SimpleInit` 两个子模块。

## 2. 构建菜单组件

```bash
# edk2 的 CLANG38 工具链需要不带版本号的 llvm-ar
export PATH="/usr/lib/llvm-21/bin:$PATH"
bash tools/build_ui_components.sh
python3 tools/package_components.py --workspace local/build-ui/workspace --out dist/ui
```

产物：`HerculesBootMenu.efi/.ffs`、`AndroidHandoff.efi/.ffs`、`HerculesBootConfig.ffs`、`simpleinit.static.uefi.cfg`。

## 3. 字体（必须本机生成）

菜单从固件卷读 RAW 字体。没有字体时它只会显示 `Local UI font pack required`，不会自动启动。

```bash
python3 -m venv ~/venv-fonts
~/venv-fonts/bin/pip install fonttools
~/venv-fonts/bin/python3 tools/make_local_font_pack.py \
  --regular <常规体.ttf/ttc> --bold <粗体.ttf/ttc> \
  --out local/fonts \
  --base-tools <edk2>/BaseTools/BinWrappers/PosixLike
```

生成的 `HerculesFont-regular.ffs` / `HerculesFont-bold.ffs` 不要上传（字体版权）。

**改了菜单里显示的文字，必须重新生成字库**，否则新汉字没有字形，会显示成空白。

## 4. 合并进自研固件（本项目的做法）

自研固件是 `~/dipper-xnu/work/edk2`（平台 `Platform/Xiaomi/sdm845/dipper.dsc` + `dipper.fdf.inc`）。
它本身已经有一个关键的东西：

```c
FILE APPLICATION = d82f808b-ecca-4bb8-8e9f-9b9bafc490f5 {
  SECTION PE32 = XnuLoaderPkg/Binary/loader.efi
  SECTION UI = "XnuLoader"
}
```

正是菜单配置里 `ios` 入口要的 GUID，所以 iOS 侧不用改。

需要做四件事：

### 4.1 拷资源

```
Platform/Xiaomi/sdm845/Hercules/
  simpleinit.static.uefi.cfg
  hercules-ui-regular.ttf
  hercules-ui-bold.ttf
  （Android 入口若用 EFI 程序，也放这里）
```

### 4.2 改 DSC

`dipper.dsc` 的 `[BuildOptions.common]` 加 `-DHERCULES_EXTERNAL_UI_FONTS=1`；
`[PcdsFixedAtBuild.common]` 里已有 1080×2248、DPI 410、厂商/机型/代号，无需改。

### 4.3 改 FDF

`dipper.fdf.inc` 追加：

```
FILE FREEFORM = 4b0364cf-1c5b-47aa-9073-d7b5039ce49b {
  SECTION RAW = Platform/Xiaomi/sdm845/Hercules/simpleinit.static.uefi.cfg
  SECTION UI = "simpleinit.static.uefi.cfg"
}
FILE FREEFORM = e71a7a5c-8196-4d48-b641-09d21a13bdf4 {
  SECTION RAW = Platform/Xiaomi/sdm845/Hercules/hercules-ui-regular.ttf
}
FILE FREEFORM = 30c1b010-8e7b-48a7-bd44-6978cf57d210 {
  SECTION RAW = Platform/Xiaomi/sdm845/Hercules/hercules-ui-bold.ttf
}
```

### 4.4 用菜单版 SimpleInit 构建

```bash
export SIMPLE_INIT=~/mi8-dualboot-lab/source/simple-init
cd ~/dipper-xnu/work/edk2
bash build.sh -d dipper
```

`build.sh` 会优先采用 `SIMPLE_INIT` 指向的源码包，于是 FDF 里的 `INF src/main/SimpleInitMain.inf` 编译出来的就是带 `hercules_skin` 的 SimpleInit（约 8.6 MB）。

## 5. 配置是怎么生效的（重要教训）

`simpleinit.static.uefi.cfg` 是 `confd` 从**已挂载的文件系统卷**根目录读取的（`PcdConfDefaultStaticPrefix = "\\simpleinit.static.uefi"`），**不是**从固件卷文件读。

本项目最终采用**代码注入**，绕开这个不确定性：

在 `source/simple-init/src/main/uefimain.c` 的 `post_main()` 里、`boot_init_configs()` 之后加入：

```c
confd_set_boolean("boot.hercules_skin", true);
confd_set_string("boot.title", "Android / iOS");
confd_set_integer("boot.timeout", 10);
confd_set_string("boot.default", "android");
confd_set_string("boot.configs.android.desc", "Android (MIUI)");
confd_set_string("boot.configs.android.mode", "efi");
confd_set_boolean("boot.configs.android.show", true);
confd_set_boolean("boot.configs.android.enabled", true);
confd_set_string("boot.configs.android.efi_fv_guid", "<Android 入口 GUID>");
confd_set_string("boot.configs.ios.desc", "iOS 16.5");
confd_set_string("boot.configs.ios.mode", "efi");
confd_set_boolean("boot.configs.ios.show", true);
confd_set_boolean("boot.configs.ios.enabled", true);
confd_set_string("boot.configs.ios.efi_fv_guid", "d82f808b-ecca-4bb8-8e9f-9b9bafc490f5");
```

这样即使配置文件读不到，菜单也一定能起来。

## 6. 菜单的前置条件（不满足就退回文本界面）

`bootmenu_hercules_draw()` 里有连续几道检查，任何一条不满足都会 `return -1`，屏幕就变成 `live NN s` 的文本界面：

1. `boot.hercules_skin` 为真
2. 帧缓冲 ≥ 320×480
3. `boot_get_config("android")` 与 `("ios")` 都存在，且 `enabled`、`show`、`mode == BOOT_EFI`
4. 背景图 `bg.jpg` 必须是 1080×2248
5. 字体能从固件卷的 RAW 资源加载

排查时按这个顺序看。
