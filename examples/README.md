# Example configuration

Sanitized copies of the tested configuration. Treat them as **templates**: replace the
placeholders, read every line, and apply them with the tool that owns the file. Nothing here
is applied automatically.

| File | Goes to |
| ---- | ------- |
| `100.conf` | `/etc/pve/qemu-server/<VMID>.conf` (or set the same values in the UI) |
| `vfio.conf` | `/etc/modprobe.d/vfio.conf` |
| `etc-modules` | `/etc/modules` |
| `grub-cmdline.txt` | the `GRUB_CMDLINE_LINUX_DEFAULT` line in `/etc/default/grub` |

Notes:

- `vga: std` is required by RadeonResetBugFix; without it the service cannot disable the only
  display adapter and shutdown hangs. See [reset-bug](../docs/reset-bug.md).
- `x-vga=1` makes the Radeon the primary display.
- There is no `-no-reboot` in `args`: the service needs in-place restarts.
- After changing vfio/modules/GRUB: `update-initramfs -u -k all`, `update-grub`, reboot.
- Verify with `sudo ./scripts/check-passthrough.sh --vmid <VMID> --explain`.
