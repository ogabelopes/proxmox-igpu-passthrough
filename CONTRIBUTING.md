# Contributing

Short and strict, because this repository is about hardware that is easy to mis-report.

## Where to post what

| You have... | Use |
| ----------- | --- |
| A verified configuration to add | Pull request to [docs/hardware-matrix.md](docs/hardware-matrix.md) |
| A question ("will this work on my APU?") | [Discussions](https://github.com/ogabelopes/proxmox-igpu-passthrough/discussions) |
| A bug in the guide or the script | An issue (the hardware-report template) |
| A correction to the docs | Pull request |

## Reporting a hardware result

- Only report configurations you actually booted. "It should work" is not a result.
- One row per configuration: APU, iGPU PCI ID, machine, PVE/kernel/QEMU, guest, whether the
  audio function is passed through, and what a guest-initiated reboot does.
- Say explicitly when recovery needs a **cold stop/start** or a **host power cycle**. That is
  the reset bug, not a success — and it is the most useful data point in the table.
- Include the output of `scripts/check-passthrough.sh` in the PR/issue description.
- Generate the row with `sudo ./scripts/check-passthrough.sh --matrix-row --vmid <id>` and
  edit the machine column to the retail model name.

## Before you paste anything

Remove **hostnames, public IPs, MAC addresses, UUIDs, serial numbers, VMIDs and disk IDs**.
Sanitize terminal output instead of pasting screenshots.

Never attach or commit vendor firmware (VBIOS dumps, `AMDGopDriver.rom`, anything `.rom`).
`.gitignore` blocks the common names, but do not rely on it — firmware is not redistributable.

## Tests

- The script is tested with `bats` against fixture trees: host paths are redirected with
  `--root` and `lspci`/`lsmod`/`qm`/`dmidecode` are stubbed in the test setup.
- Run `bats tests/` locally; CI runs it on every push.
- Add or update a fixture when you add a check.

## Scope

- The guide targets Proxmox VE 8.4+ on Ryzen 6000/7000 APUs. Other hardware is welcome in the
  matrix if it genuinely works.
- The verification script is **read-only** and must stay that way: it may inspect
  `/etc/pve`, `/sys` and `/proc`, but it must never modify host state.
- Keep changes small. A focused PR that fixes one thing is easier to verify than a rewrite.
