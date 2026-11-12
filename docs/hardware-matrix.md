# Hardware matrix

Verified configurations, **one row per setup that was actually booted**. This replaces a
wiki: every entry arrives through a pull request, so it is reviewed, versioned and linted
alongside the guide.

If you are only asking *"does this work on X?"*, use
[Discussions](https://github.com/ogabelopes/proxmox-igpu-passthrough/discussions) instead of
adding a row.

## Results

| APU / CPU | iGPU | Machine | PVE · kernel · QEMU | Guest | vfio binding | Guest reboot | Reported |
| --------- | ---- | ------- | ------------------- | ----- | ------------ | ------------ | -------- |
| Ryzen 9 6900HX | Radeon 680M `1002:1681` | Beelink EQR6 (EQR6-D5, BIOS FP7T107) | 8.4.21 · 6.8.12-43-pve · 9.2 | Windows 11 | GPU + audio `1002:1640` | **Yes**, with RadeonResetBugFix and a virtual GPU (`vga: std`); Fast Startup off | 2026-11 |

### Legend

- **vfio binding** — "GPU + audio" means both the display and HD-audio functions are bound
  to `vfio-pci`, which is what avoids the OVMF Error 43.
- **Guest reboot** — what happens when Windows **Restart** is used (not a cold start):
  - *Yes* — the display comes back without external help. Usually means RadeonResetBugFix
    plus a virtual GPU, with Fast Startup disabled.
  - *No — cold stop/start only* — `qm stop` + `qm start` recovers it.
  - *No — host power cycle only* — the unmitigated AMD reset bug; see
    [reset-bug](reset-bug.md).

## How to add a result

1. Boot the configuration and verify the display, audio, and at least one guest reboot.
2. Fork, add **one** row, and open a pull request (see [CONTRIBUTING](../CONTRIBUTING.md)).
3. Sanitize everything: no hostnames, IPs, MACs, UUIDs, serials, VMIDs or disk IDs.
4. Never attach firmware (VBIOS/GOP ROMs) — they are not accepted.

Keep rows short. Details that matter (quirks, extra kernel flags, machine type) belong in
the pull request description, not in the table.
