# The AMD reset bug, and the mitigation that works

If a Windows **Restart** leaves you with a black screen and only a host power cycle brings
the display back, you are looking at the AMD reset bug. On the 680M it is a hardware
limitation, not a Proxmox misconfiguration. There is no way to make a warm reset work by
itself; the fix is to stop the guest from performing one.

## Why a warm reboot breaks the display

On a guest reboot, QEMU resets the virtual machine and the guest firmware runs again. It
does **not** power-cycle the physical GPU. For the kernel to reset the device, the PCI
function must support a reset method:

```bash
cat /sys/bus/pci/devices/0000:XX:00.0/reset_method
# bus
lspci -vvv -s XX:00.0 | grep -o 'FLReset[+-]'
# FLReset-
```

The 680M exposes only `bus` and does not support function-level reset. The firmware then
tries to re-post the VBIOS against a GPU that is still owned by the previous driver; the
post fails and the screen stays black. A host power cycle resets the device at the hardware
level, which is why it always recovers.

## The mitigation: a virtual GPU plus a guest service

The working combination on the tested hardware is three things:

1. **A virtual GPU in the VM** (`vga: std`). The RadeonResetBugFix service needs a second
   adapter to switch to while it disables the Radeon. With `vga: none` the Radeon is the only
   display adapter, Windows refuses to disable it, and `qm shutdown` hangs.
2. **RadeonResetBugFix installed and running in Windows**. On shutdown it enables the virtual
   adapter and disables the Radeon; on startup it enables the Radeon and disables the virtual
   adapter. That is what keeps the GPU in a reusable state.
3. **Fast Startup disabled** (`powercfg /h off`). Hybrid shutdown leaves the GPU
   half-initialised and defeats the handoff.

Keep `x-vga=1` on the GPU function so the Radeon stays the primary display, and do **not**
use `-no-reboot`: an in-place restart must reach the service's disable/enable cycle.

Behaviour to expect:

- Shutdown and startup can take **several minutes** while the service swaps adapters.
- A black screen right after start is normal during that window; wait before assuming it
  failed.
- If Windows shows two displays and the desktop landed on the virtual one, use `Win+P` and
  choose **Duplicate**, or run `Restart-Service RadeonResetBugFix` from an elevated
  PowerShell. The [service README](https://github.com/inga-lovinde/RadeonResetBugFix#known-issues) documents this recovery.
- Do **not** force-reboot the guest while the service is mid-cycle; reboot the host
  gracefully instead (also per the service README).

For updates: "Update and shut down", or a normal restart, both work. If the VM ends up
stopped, start it and give the service its few minutes.

## What does not work (tested on a 6900HX / 680M)

These were tried on the actual machine and are recorded so nobody repeats them:

| Attempt | Result |
| ------- | ------ |
| `echo 1 > /sys/bus/pci/devices/.../reset` | `EINVAL` — no usable reset method |
| PCI `remove` + `/sys/bus/pci/rescan` | device returns on `vfio-pci`, GPU still unusable |
| PM reset of the parent root port (`00:08.1`) | accepted, GPU still unusable |
| `nomodeset` on the host cmdline | blocks `amdgpu` entirely (`drm_firmware_drivers_only()` makes `amdgpu_init()` return `EINVAL`) |
| Host `amdgpu` rebind hook ([isc30 #131](https://github.com/isc30/ryzen-gpu-passthrough-proxmox/issues/131)) | on this APU the bind fails: `memtype_reserve failed` / "Unable to set WC memtype for the aperture base" (4 GiB UMA carve-out vs BAR0) |
| `vendor-reset` | no support for these APUs |
| `-no-reboot` alone | turns the crash into a clean stop, but does not restore the GPU without the service and virtual GPU |

The host-side rebind remains a promising route if `amdgpu` can be made to initialize on the
host (the aperture failure above). Candidate fixes are a smaller UMA frame buffer in BIOS
(4 GiB to 512 MiB/1 GiB) or a newer kernel.

## Guest checklist

- [ ] RadeonResetBugFix service installed, **Running**, Startup type **Automatic**
- [ ] Fast Startup disabled (`powercfg /h off`; `powercfg /a` shows hibernation unavailable)
- [ ] AMD driver installed from the **offline** package
- [ ] Virtual GPU present in the VM (`vga: std`)
- [ ] Windows Update set to not restart while you are logged on, if you prefer to choose the
      moment

If it still fails, check the service log: it writes a `logs` folder next to
`RadeonResetBugFixService.exe`, and the latest file names the exact device step that failed.
