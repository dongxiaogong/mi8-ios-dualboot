# 08 · 刷写、校验与回退

## 1. 动手前必须有的三样东西

1. **原厂 `boot` 备份**（哈希核验过）
2. **原厂 `recovery` 备份**（本项目覆盖了它 —— 这一步我漏了，别学）
3. 可用的 fastboot 与 TWRP（TWRP 用 `fastboot boot twrp.img` 临时启动即可）

```bash
# 在 TWRP 里
adb shell "dd if=/dev/block/by-name/boot of=/tmp/boot.img bs=1048576"
adb pull /tmp/boot.img boot-original.img
adb shell "dd if=/dev/block/by-name/recovery of=/tmp/recovery.img bs=1048576"
adb pull /tmp/recovery.img recovery-original.img
sha256sum boot-original.img recovery-original.img
```

## 2. 刷写顺序（角色对调方案）

```bash
fastboot devices                     # 确认是 <SERIAL> 这类真实序列号
fastboot erase misc                  # 清掉可能残留的 BCB
fastboot flash boot     android.img  # 强制 Android 的合成镜像
fastboot flash recovery menu.img     # 菜单合成镜像
fastboot reboot
```

## 3. 回读校验

分区是 64 MiB，而候选镜像约 63 MiB，所以**整段哈希必然不同**（尾部填充为 0）。要按有效长度比：

```bash
# TWRP 里
adb shell "dd if=/dev/block/by-name/boot of=/tmp/rb.img bs=1048576"
adb pull /tmp/rb.img rb.img
```

```python
# 主机上
import hashlib
cand = open("boy.img","rb").read()      # 候选镜像
back = open("rb.img","rb").read()       # 回读
assert back[:len(cand)] == cand, "有效内容不一致"
assert set(back[len(cand):]) <= {0}, "尾部不是全零"
print("OK")
```

## 4. 回退

| 想回到 | 命令 |
| --- | --- |
| 完全原厂 | `fastboot flash boot boot-original.img` + `fastboot flash recovery recovery-original.img` + `fastboot erase misc` |
| 只回到能开机的 Android | `fastboot flash boot boot-original.img` |
| 清掉卡住的启动指令 | `fastboot erase misc` |

`boot-original.img` 的 SHA256 必须与备份时一致；本机记录：`edf7e89add16e01b9a07bac6ec9a903be5dea9f77633e674bd6e1b3ed286401c`。

## 5. 临时启动（不写盘）

验证新镜像时优先用：

```bash
fastboot boot new-menu.img
```

它把镜像加载到内存运行，不改分区。注意：**菜单/loader 若没有 USB 服务，会是「手机在跑但电脑看不到设备」**，这时只能看屏幕、或长按电源重启。

## 6. 关键数值一览（本机实测，勿照抄）

| 项 | 值 |
| --- | --- |
| 设备 | 小米 8 `dipper`，序列号 `<SERIAL>` |
| boot 分区 | 64 MiB（`partition-size:boot: 0x4000000`） |
| 逻辑扇区 | 4096 |
| darwin | #22，LBA 23746560–30038010，6,291,451 扇区 |
| UEFI FD | 7 MiB（`0x700000`），基址 `0xCE000000` |
| 载荷基址 | `0xF0000000` |
| iOS loader GUID | `d82f808b-ecca-4bb8-8e9f-9b9bafc490f5` |
| 菜单配置 GUID | `4b0364cf-1c5b-47aa-9073-d7b5039ce49b` |
| 字体 GUID | 常规 `e71a7a5c-8196-4d48-b641-09d21a13bdf4` / 粗体 `30c1b010-8e7b-48a7-bd44-6978cf57d210` |
| Android 入口 GUID | `801a189c-e4a4-4195-85c2-64c5450a15ee` |
