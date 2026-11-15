#include <Uefi.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/UefiLib.h>
#include <Library/DebugLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/UefiApplicationEntryPoint.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/BlockIo.h>
#include <Protocol/PartitionInfo.h>

/*
 * AndroidSwitch: hand the next boot to Android.
 *
 * The dual-boot boot shim cannot be told apart from a normal cold boot once a
 * warm reset has cleared RAM, but the Android bootloader itself understands the
 * bootloader control block in the "misc" partition. Writing "boot-recovery"
 * there makes ABL boot the recovery partition once (where the Android image is
 * kept) and clear the command afterwards, so the following power-on returns to
 * the UEFI menu.
 */

#define BCB_BYTES 2048

typedef struct {
  CHAR8    Command[32];
  CHAR8    Status[32];
  CHAR8    Recovery[768];
  CHAR8    Stage[32];
  CHAR8    Reserved[1184];
} BOOTLOADER_MESSAGE;

STATIC CONST CHAR16  mMiscName[] = L"misc";

STATIC
EFI_STATUS
WriteBootRecovery (
  IN EFI_HANDLE  Handle
  )
{
  EFI_BLOCK_IO_PROTOCOL  *BlockIo = NULL;
  EFI_STATUS             Status;
  UINT8                  *Buffer;
  UINTN                  Size;
  UINTN                  Blocks;
  BOOTLOADER_MESSAGE     Bcb;

  Status = gBS->HandleProtocol (Handle, &gEfiBlockIoProtocolGuid, (VOID **)&BlockIo);
  if (EFI_ERROR (Status) || (BlockIo == NULL) || (BlockIo->Media == NULL) || !BlockIo->Media->MediaPresent) {
    return EFI_NOT_FOUND;
  }

  Size   = BlockIo->Media->BlockSize;
  Blocks = (BCB_BYTES + Size - 1) / Size;
  if (Blocks == 0) {
    Blocks = 1;
  }

  Buffer = AllocateZeroPool (Blocks * Size);
  if (Buffer == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }

  ZeroMem (&Bcb, sizeof (Bcb));
  AsciiStrCpyS (Bcb.Command, sizeof (Bcb.Command), "boot-recovery");
  CopyMem (Buffer, &Bcb, sizeof (Bcb));

  Status = BlockIo->WriteBlocks (BlockIo, BlockIo->Media->MediaId, 0, Blocks * Size, Buffer);
  FreePool (Buffer);
  return Status;
}

EFI_STATUS
EFIAPI
AndroidSwitchEntryPoint (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  /* SWAP_ROLES: the Android image now lives in the boot partition, so the
   * only thing this entry has to do is hand the firmware over to it. */
  gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
  CpuDeadLoop ();

  EFI_HANDLE  *Handles = NULL;
  UINTN       Count    = 0;
  UINTN       Index;
  EFI_STATUS  Status;
  BOOLEAN     Done = FALSE;

  Status = gBS->LocateHandleBuffer (
                  ByProtocol,
                  &gEfiPartitionInfoProtocolGuid,
                  NULL,
                  &Count,
                  &Handles
                  );
  if (EFI_ERROR (Status)) {
    DEBUG ((DEBUG_ERROR, "AndroidSwitch: no partition info protocol: %r\n", Status));
    return Status;
  }

  for (Index = 0; Index < Count && !Done; Index++) {
    EFI_PARTITION_INFO_PROTOCOL  *Info = NULL;

    Status = gBS->HandleProtocol (Handles[Index], &gEfiPartitionInfoProtocolGuid, (VOID **)&Info);
    if (EFI_ERROR (Status) || (Info == NULL) || (Info->Type != PARTITION_TYPE_GPT)) {
      continue;
    }

    if (StrCmp (Info->Info.Gpt.PartitionName, mMiscName) != 0) {
      continue;
    }

    Status = WriteBootRecovery (Handles[Index]);
    DEBUG ((DEBUG_INFO, "AndroidSwitch: misc boot-recovery: %r\n", Status));
    Done = (Status == EFI_SUCCESS);
  }

  FreePool (Handles);

  if (!Done) {
    DEBUG ((DEBUG_ERROR, "AndroidSwitch: could not write the bootloader control block\n"));
    return EFI_NOT_FOUND;
  }

  gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
  CpuDeadLoop ();
  return EFI_SUCCESS;
}
