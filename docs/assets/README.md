# Assets

Screenshots used by the main README.

| File | Purpose |
| ---- | ------- |
| `logo.svg` / `.png` | Primary named lockup for **light** backgrounds (1100x240, transparent, no frame): AMD left, designed flow arrow, Proxmox X + Windows core, then "Proxmox iGPU passthrough" and the tested-hardware line. |
| `logo-dark.svg` / `.png` | Same lockup for **dark** backgrounds. The README picks between the two with `<picture>` + `prefers-color-scheme`. |
| `logo-mark.svg` / `.png` | The mark alone (560x240, transparent, dark-background palette): official AMD wordmark on the left, a gradient via-to-head flow arrow, and the official Proxmox X with the Windows core centred on it. |
| `logo-wide.svg` / `.png` | Secondary brand lockup (760x180): official Proxmox, AMD and Windows marks joined by arrows. |
| `social-preview.svg` / `.png` | 1280x640 card for the GitHub repository social preview (Settings -> Social preview; uploads are manual). |
| `device-manager.png` | Screenshot to take: Windows 11 Device Manager, Display adapters, showing the passed-through GPU ("AMD Radeon 680M"). Crop to the relevant pane. |

Re-render the raster assets after editing the SVGs:

```bash
rsvg-convert -w 1100 -h 240 docs/assets/logo.svg -o docs/assets/logo.png
rsvg-convert -w 1100 -h 240 docs/assets/logo-dark.svg -o docs/assets/logo-dark.png
rsvg-convert -w 560 -h 240 docs/assets/logo-mark.svg -o docs/assets/logo-mark.png
rsvg-convert -w 760 -h 180 docs/assets/logo-wide.svg -o docs/assets/logo-wide.png
rsvg-convert -w 1280 -h 640 docs/assets/social-preview.svg -o docs/assets/social-preview.png
```

Rules:

- Blur or crop the VM/computer name, hostnames and any UUID.
- Keep files under roughly 300 KB (PNG or WebP).
- No screenshots of terminals; paste sanitized text instead.
