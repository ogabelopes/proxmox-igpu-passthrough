# Security

## Scope

This repository contains documentation and two host-side scripts:

- `scripts/check-passthrough.sh` — read-only inspection of a Proxmox VE host (and,
  optionally, its guest through the QEMU guest agent).
- `scripts/extract-vfct.py` — reads the `VFCT` ACPI table and writes a VBIOS file.

No service is exposed and no credentials are handled.

## Running the scripts

`check-passthrough.sh` runs as **root** and must remain read-only: it inspects `/etc/pve`,
`/sys`, `/proc` and guest state. It never writes to the host. Review the script before
running it, and verify the checksum published with the release:

```bash
curl -LO https://github.com/ogabelopes/proxmox-igpu-passthrough/releases/latest/download/check-passthrough.sh
sha256sum check-passthrough.sh   # compare with the release notes
less check-passthrough.sh
sudo bash check-passthrough.sh
```

`extract-vfct.py` only reads the ACPI table and writes the extracted image to the output
directory you choose. The source table is not modified.

## Firmware

Vendor firmware (VBIOS/GOP ROMs) is **not** distributed in this repository. Extract it from
your own hardware and keep it out of public repos.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting (**Security → Report a vulnerability**) rather
than a public issue. Include the script version (`--version`) and a sanitized report — no
hostnames, IPs, UUIDs or serials.
