# Why the host has no local console

Once the only GPU is handed to a VM, the physical monitor stops belonging to the
hypervisor. That is expected — but it is rarely written down, and it turns a routine
recovery into a surprise.

## What happens

A typical single-GPU passthrough setup combines:

- `vfio-pci` binding the GPU at boot (`options vfio-pci ids=... disable_vga=1`),
- a kernel cmdline that prevents the host from using it as a framebuffer, for example
  `nomodeset video=efifb:off video=vesafb:off video=amdgpu:off`,
- a VM attached with `vga: none` and the GPU as its primary display.

Result after boot:

- the host has **no framebuffer** (`/dev/fb*` does not exist),
- the VM's HDMI output works while the VM runs,
- PVE's **noVNC console is blank** for that VM (`vga: none` means there is no emulated
  display to show),
- there is no serial console unless you configured one.

The `video=...:off` flags are a trade-off: they keep the host from grabbing the GPU, at the
price of a headless host. On some hardware the host would not use the GPU after vfio binds
anyway, and the flags can be relaxed — test it.

## Why it matters

If the guest is down and the network is unreachable, the machine is not recoverable over
the network. The local options are limited on purpose.

## Recovery paths

### The GRUB menu

The UEFI firmware drives the GPU before Linux takes over, so the GRUB menu is usually
still visible at boot. From there you can edit the default entry and remove the flags that
disable the framebuffer, and remove the vfio binding, to boot into a text console:

1. Hold `Shift` (BIOS) or press `Esc` (UEFI) during boot to reach GRUB.
2. `e` to edit the selected entry.
3. Remove `nomodeset video=efifb:off video=vesafb:off video=amdgpu:off` and, if present,
   the `vfio-pci.ids=` argument.
4. `Ctrl-X` to boot.

You get a text console, not a desktop, and the change is temporary — good for diagnosis,
not for daily use.

### A live USB

The cleanest path for actual use (or for a presentation): boot a live Linux image from USB.
It brings its own kernel cmdline, loads the native GPU driver, and drives the monitor
without touching the installed disks. Nothing about the Proxmox installation changes.

Keep one at hand if this machine is your only local access to the hypervisor.

### Hardware options (for a permanent safety net)

- a second, low-cost GPU for the host,
- a motherboard BMC/IPMI with remote console,
- a USB-serial console (`console=ttyS0` plus a USB-UART adapter).

## Checklist

- [ ] You know the GRUB edit that restores a text console.
- [ ] You have a tested live USB.
- [ ] The host is reachable over the network independently of the GPU (SSH + web UI).
- [ ] The VM's config, VBIOS/GOP ROMs, `vfio.conf`, `/etc/modules` and the kernel cmdline
      are backed up somewhere outside `/etc/pve`.
