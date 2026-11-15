# 04 · BootShim 与载荷搬运（本项目最关键的修复）

## 1. 为什么必须改 shim

`BootShim.Dualboot.S`（来自 mi8-dualboot-lab）只做两件事：

1. 在 `0x17FE00000` 找「启动 Android」的 magic
2. 没找到就把 UEFI 固件复制到 `0xCE000000` 并跳过去

**它不会搬运载荷**。而上游 `tools/BootShim/BootShim.S` 有一段：

```asm
#ifdef PAYLOAD_BASE
	/* x4 此时指向 FD 之后：可选的 XNUP 载荷可能跟在这里 */
	ldr	w2, [x4]
	movz	w3, #0x4E58
	movk	w3, #0x5055, lsl #16
	cmp	w2, w3
	b.ne	_NoPayload
	ldr	w6, [x4, #4]
	add	x6, x6, #23
	and	x6, x6, #~15
	movz	x5, #(PAYLOAD_BASE >> 16), lsl #16
_PayloadLoop:
	ldp	x2, x3, [x4], #16
	stp	x2, x3, [x5], #16
	subs	x6, x6, #16
	b.ne	_PayloadLoop
_NoPayload:
#endif
```

而 `loader.c` 固定从 **`PAYLOAD_BASE = 0xF0000000`** 读 XNUP：

```c
#define PAYLOAD_BASE   0xF0000000ULL
#define PAYLOAD_MAGIC  0x50554E58u   /* "XNUP" */
```

少了这段搬运，loader 在 `0xF0000000` 只能读到空内存，于是打印 `live NN s` 一直等待。

### 症状对照

| 屏幕 | 含义 |
| --- | --- |
| `live NN s` 每 5 秒一行 | loader 起来了，但在等载荷（载荷没到 `0xF0000000`） |
| 内核日志滚动 | 载荷对了，内核在启动 |
| `Panicked task … pid 1: init` | 内核起了，用户空间缺东西（见第 3 节） |

## 2. 合并后的 shim（补丁）

在 `_CopyUEFI` 的 `bl _CopyLoop` 之后、`_Entry` 之前插入上游那段搬运逻辑，编译时加 `-DPAYLOAD_BASE=0xF0000000`：

```bash
aarch64-linux-gnu-gcc -c BootShim.Dualboot.Payload.S -o shim.elf \
  -DUEFI_BASE=0xCE000000 -DUEFI_SIZE=0x00700000 -DPAYLOAD_BASE=0xF0000000
aarch64-linux-gnu-objcopy -O binary shim.elf shim.bin
```

完整源码见 `patches/dipper-xnu/BootShim.Dualboot.Payload.S`。

> 汇编 `.S` 时必须用 `aarch64-linux-gnu-gcc`，用主机的 `gcc` 会报 `no such instruction: movk`。

## 3. `boot` 条目：让 flashboot 随载荷走（第二个关键修复）

正常流程里 loader 收到的载荷只有 `kernel` + `ramdisk`，而 **boot 卷（`flashboot.apfs`）是通过 USB 单独下载的**：

```
oem ramdisk → 下载 flashboot.apfs → stage payload.bin → oem run
```

`loader.c` 里对应逻辑：

```c
if (pi.resident_rd != 0) resident_rd_size = pi.resident_rd;
if (resident_rd_size != 0) {
    uint64_t res_pa = phys_base + RESIDENT_RD_OFFSET;   /* 0x08000000 */
    ...
    /* 两个盘：常驻镜像是 root(md0)，载荷 ramdisk 是 md1 */
}
```

自包含镜像没有 USB 下载这一步，于是 **boot 卷缺失 → `launchd` 找不到 → `init` panic**：

```
Panicked task …: 1 pages, 1 threads: pid 1: init
```

修复：给 loader 增加一个 `boot` 条目：

```c
/* struct payload_info */
const uint8_t *boot;
uint32_t boot_size;

/* 解析 */
} else if (str_eq(e->name, "boot")) {
    pi->boot = p + sizeof(*e);
    pi->boot_size = e->size;
}

/* 放置 */
if (pi.boot_size != 0) resident_rd_size = pi.boot_size;
if (resident_rd_size != 0) {
    uint64_t res_pa = phys_base + RESIDENT_RD_OFFSET;
    uint64_t res_size = (resident_rd_size + PAGE_SIZE_MAX - 1) & ~(PAGE_SIZE_MAX - 1);
    if (pi.boot_size != 0) {
        memset((void *)res_pa, 0, res_size);
        memcpy((void *)res_pa, pi.boot, pi.boot_size);
        print("boot image at pa %x size %x\n", res_pa, res_size);
    }
    ...
}
```

打包时：

```bash
python3 mkpayload.py -o payload.bin \
  kernel=kernel.macho ramdisk=root.apfs boot=flashboot.apfs \
  --cmdline "$CMDLINE"
```

补丁见 `patches/dipper-xnu/loader-boot-entry.patch`。

## 4. XnuLoaderDxe：别让它抢走启动流程

`XnuLoaderPkg/Driver/XnuLoaderDxe` 会把自己注册成 Boot#### 并**插到 BootOrder 第一位**，结果固件直接启动 loader，SimpleInit（菜单）永远轮不到 —— 表现同样是 `live NN s`。

本项目把它改成**删除自己注册的启动项**，把流程还给菜单：

```c
/* DUALBOOT_DELETE_OPTION */
Order = NULL; OrderSize = 0; Number = 0xFFFF;
GetEfiGlobalVariable2(EFI_BOOT_ORDER_VARIABLE_NAME, (VOID **)&Order, &OrderSize);
if (Order != NULL) {
    for (Index = 0; Index < OrderSize / sizeof(UINT16); Index++) {
        UnicodeSPrint(Name, sizeof(Name), L"Boot%04x", Order[Index]);
        if (!EFI_ERROR(GetEfiGlobalVariable2(Name, &Existing, &ExistingSize))) {
            if (ExistingSize == OptionSize && CompareMem(Existing, Option, OptionSize) == 0) {
                Number = Order[Index];
                gRT->SetVariable(Name, &gEfiGlobalVariableGuid, 0, 0, NULL);  /* 删除 */
            }
            FreePool(Existing);
        }
    }
    NewOrder = AllocatePool(OrderSize);
    if (NewOrder != NULL) {
        for (Index = 0, Out = 0; Index < OrderSize / sizeof(UINT16); Index++)
            if (Order[Index] != Number) NewOrder[Out++] = Order[Index];
        gRT->SetVariable(EFI_BOOT_ORDER_VARIABLE_NAME, &gEfiGlobalVariableGuid,
                         OPTION_ATTRIBUTES, Out * sizeof(UINT16), NewOrder);
        FreePool(NewOrder);
    }
    FreePool(Order);
}
FreePool(Option);
return EFI_SUCCESS;
```

注意：**只是把顺序挪到末尾不够**，因为 NVRAM 里已经有旧的 Boot#### 变量，必须主动删掉。

XnuLoaderDxe 的 `FILE_GUID` 与菜单里 `ios` 用的 `d82f808b-…` 是两回事：前者是注册器驱动，后者是 loader 本体所在的 FV 文件 GUID。

## 5. 合成的组成

`compose_dipper_boot.py` 做的事（本机改了一处，见下）：

```
解压原厂 kernel（gzip） → 得到 Image + 尾部 dtb
  ↓
kernelpatcher 把 shim 打进 Image 头部，改写 Image Size / branch
  ↓
Image + shim + FD + payload 重新 gzip（libdeflate -12）
  ↓
拼接 dtb → 得到新的 kernel 段
  ↓
沿用原 boot header（更新 kernel_size 与 SHA1），加原 ramdisk
```

三个必要条件：

- `libdeflate-gzip` 必须安装（`apt install libdeflate-tools`）
- 原 boot 镜像的 `page=4096`、`second_size=0`、`recovery_dtbo=0`、`dtb_size=0`
- 载荷里**不能**有 `loader_return_after`

### 本机改动：接受 header v1

上游工具只接受 legacy v0：

```python
assert struct.unpack_from('<I',orig,40)[0]==0,'Only legacy header version zero is supported'
```

本机的原厂 boot 是 **v1**（`header_version=1`），但 v1 多出来的字段（`recovery_dtbo`、`header_size`、`dtb_size/addr`）实测全为 0，其余布局与 v0 完全一致，因此放宽为：

```python
assert struct.unpack_from('<I',orig,40)[0] in (0,1),'Only legacy header versions 0/1 are supported'
```

补丁见 `patches/mi8-dualboot-lab/compose-v1.patch`。
