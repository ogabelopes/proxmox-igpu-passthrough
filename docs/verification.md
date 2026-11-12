# Verification reference

`check-passthrough.sh` prints a **stable check ID** for every result. `--explain` adds a
short *why / fix* block for each warning and failure, and `--json` includes the same data
(`id`, `message`, `why`, `fix`) for automation.

Exit status: `0` no failures, `1` at least one FAIL, `2` usage/permission error. A WARN is
worth knowing; a FAIL means the setup will not behave as intended.

## Host and IOMMU

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| IOMMU-1 | IOMMU groups exist | Groups are what let the kernel isolate a device for assignment | Enable IOMMU/AMD-Vi in firmware, add `iommu=pt`, reboot |
| IOMMU-2 | `iommu=pt` on the cmdline | Keeps host DMA paths in pass-through mode | Add it to `GRUB_CMDLINE_LINUX_DEFAULT` |
| IOMMU-3 | `amd_iommu=on` / `intel_iommu=on` | Makes the setting explicit | Add it to the cmdline |

## vfio-pci

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| VFIO-1 | `vfio_pci` loaded | Without it QEMU cannot own the device | Load the vfio modules at boot |
| VFIO-2 | vfio modules in `/etc/modules` | They must load before the native driver | Add `vfio`, `vfio_iommu_type1`, `vfio_pci` |
| VFIO-3 | `options vfio-pci ids=...` | Tells vfio-pci which functions to claim | Add the GPU + audio IDs to `vfio.conf` |
| VFIO-4 | `softdep ... pre: vfio-pci` | Ensures vfio-pci probes before amdgpu/radeon | Add the softdep lines |

## Display devices

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| DEV-1 | Display function bound to `vfio-pci` | A host-owned GPU cannot be passed through | Fix IDs/softdeps, reboot, check `lspci -k` |
| DEV-2 | IOMMU group composition | Group members must be passed or reset-safe | Pass the whole group, or use ACS override as a last resort |
| DEV-3 | `reset_method` | `bus` only means a warm reset cannot work | See [reset-bug](reset-bug.md) |
| DEV-4 | `FLReset+/-` | No FLR is the root of the reset bug | See [reset-bug](reset-bug.md) |
| DEV-5 | GPU audio function bound to `vfio-pci` | Otherwise Windows reports Error 43 / no audio | Add the audio ID and pass it too |
| DEV-6 | Onboard codec identified | Prevents a false audio warning | No action |

## Reboot readiness (host)

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| RBT-1 | `nomodeset` absent | `drm_firmware_drivers_only()` makes `amdgpu_init()` return `EINVAL` | Remove `nomodeset`; use `initcall_blacklist=sysfb_init video=efifb:off` |
| RBT-2 | `sysfb_init` blacklisted | Stops the EFI framebuffer claiming the GPU aperture | Add it to the cmdline |
| RBT-3 | `amdgpu` not blacklisted | A blacklisted driver can never be rebound | Remove the blacklist if you want the host rebind |
| RBT-4 | `amdgpu` loaded | Informational: is the driver available for a rebind? | Load it via `/etc/modules` |

## VM configuration

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| VM-1 | `vga` is not `none` | A virtual display can fight the passthrough | Use `vga: std` |
| VM-2 | `bios: ovmf` | The passthrough and GOP ROM path expect OVMF | Set it |
| VM-3 | q35 machine | The configuration target | Set `machine: pc-q35-*` |
| VM-4 | `pcie=1` | Presents the GPU as a PCIe endpoint | Add it |
| VM-5 | `-hypervisor` in args | Hides the hypervisor from the guest | Add `-cpu host,-hypervisor,kvm=off` |
| VM-6 | Windows guest has a virtual GPU | RadeonResetBugFix cannot disable the only adapter | `qm set <vmid> --vga std` |
| VM-7 | No `-no-reboot` | It prevents the service's in-place restart cycle | Remove it |
| VM-8 | `x-vga=1` | The Radeon should be the primary display | Add it |
| VM-9/10 | `romfile` files exist | The firmware needs the GPU's option ROM | Restore the file to `/usr/share/kvm` |

## Memory and console

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| MEM-1/2 | Running VM allocations | Informational | - |
| MEM-3/4 | Host headroom ≥ 2 GiB | An OOM kill of QEMU can wedge the GPU | Lower memory or set a balloon floor |
| CON-1/2 | `/dev/fb*` | No console is expected with the framebuffer blacklisted | Use GRUB or a live USB |
| CON-3 | Cmdline restricts the framebuffer | Informational | - |

## Guest side (`--guest`)

| ID | Checks | Why it matters | Fix |
| -- | ------ | -------------- | --- |
| GST-1 | Guest agent responds | Required for guest-side checks | Install the VirtIO guest tools |
| GST-2 | RadeonResetBugFix `Running` | The service makes reboots survive | Install/start it |
| GST-3 | Service `StartType` Automatic | The GPU must be re-enabled on every boot | Set it |
| GST-4 | `HiberbootEnabled=0` | Fast Startup defeats the handoff | `powercfg /h off` |
| GST-5 | Active display adapters | Informational | - |
| GST-6 | Agent absent | Guest checks cannot run | Install the guest agent |
