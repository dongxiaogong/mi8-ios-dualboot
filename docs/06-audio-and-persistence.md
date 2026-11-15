# 06 · 音频与数据保留

## 1. 音频

内核默认开启音频（不要写 `audio=0` 即可）。它需要：

| 东西 | 位置 |
| --- | --- |
| ADSP 固件 | 运行时从手机 `modem` 分区读取 |
| TAS2557 功放固件 `tas2557_uCDSP_goer.bin`（42,730 字节） | `flashboot.apfs` 的 `/fw/` |
| 驱动 | `/dev/redwood-audio`、`RedwoodAudio.driver` |

日志里正常的标志：

```
mi8rp: audio=5: resident session
[ ok ] our audio device, not Apple's plug-ins
[ ok ] the firmware on /fw (adsp=1, sound=N)
mi8rp: 13: wake #2 ... health=6 unmute=9 ms flushed=192
```

`wake` / `health` / `unmute` 说明功放被唤醒并解除静音。

### 曾经误判的一次

早期看到内核滚出 `audio: final count=…` 之后 `= END OF LOG =`，以为是音频导致崩溃。
真实原因是 **`init` panic**（缺 `flashboot.apfs`），音频只是最后打印的模块。修好 `boot` 条目后音频一切正常。

教训：**看到 `pid 1: init` 的 panic，优先怀疑用户空间缺件，而不是驱动。**

## 2. 数据保留

### 2.1 机制

iOS 的 `/private/var` 是**有界 RAMFS**，不是几十 GB 的闪存卷。数据要落盘，必须由用户空间的 `var_store` 把整个数据卷打包写入 `darwin` 分区。

握手协议（`kern.redwood.var_save`）：

```
用户空间 var_store 启动时写 VAR_SAVE_IDLE  →  内核知道「有人在」
内核要保存时置 VAR_SAVE_WANTED            →  用户空间做快照
用户空间写 VAR_SAVE_DONE                   →  内核继续
```

### 2.2 只在「运行结束」保存（默认）

`redwood_var_save_on_return()` 由 `osfmk/arm64/loader_return.c` 调用，也就是**内核把控制权还给 loader** 的时候。这需要启动参数里有 `loader_return_after=…`。

而双启动方案里合成工具**刻意拒绝**带 `loader_return_after` 的载荷（会破坏菜单语义），所以运行永远不会"结束"，数据也就不落盘。

### 2.3 改成定期保存（本项目的做法）

`var_store watch [SECS]` 支持一个可选秒数：传正数就会**每隔 N 秒自己存一次**，不必等运行结束。

启动项在 `userland/root/LaunchDaemons/com.redwood.varstore.plist`：

```xml
<key>ProgramArguments</key>
<array>
    <string>/redwood/bin/var_store</string>
    <string>watch</string>
    <string>300</string>      <!-- 本项目新增：每 5 分钟自动保存 -->
</array>
```

改完只需重新打包 `root.apfs`（不必重编整个用户空间）：

```bash
cd ~/dipper-xnu/work/hackios/userland
cp root.apfs root.apfs.bak
python3 ../tools/apfs/mkapfs.py -z --plain fw -o root.apfs redwood=root
```

配合启动参数：

```
ufs_write=1 var_store=1 var_save_ms=120000
```

### 2.4 使用注意

- 每次保存会把约 **100 MB** 写进闪存，界面可能卡顿几秒 —— 这是正常的
- 强制断电仍可能丢失「上一次保存之后」的改动
- 想立刻保存，只能等下一次定时点，或者走有序退出

### 2.5 为什么不能靠「关机保存」

上游已知问题：iOS 的**滑动关机**会卡圈。没有可靠的关机路径，就没有「运行结束」这个时机，所以必须靠定时保存。
