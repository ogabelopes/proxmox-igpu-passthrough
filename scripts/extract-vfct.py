#!/usr/bin/env python3
"""Extract GPU VBIOS images from the host's VFCT ACPI table.

The VFCT table holds the VBIOS images the firmware exposes for the GPUs in the
machine. On an APU this is where a usable VBIOS can be recovered without a
vendor download; pass the resulting file to QEMU with ``romfile=``.

Usage:
    sudo ./scripts/extract-vfct.py [--file PATH] [--output-dir DIR] [--list]

The source table is only read; one ``vbios_<vendor>_<device>.bin`` file is
written per image (unless ``--list`` is given).
"""

import argparse
import os
import struct
import sys

DEFAULT_TABLE = "/sys/firmware/acpi/tables/VFCT"
ACPI_HEADER_LEN = 36
# UEFI_ACPI_VFCT: header + TableUUID[16] + VBIOSImageOffset + Lib1ImageOffset + Reserved[4]
IMAGE_HEADER_OFF = 0x4C
IMAGE_HEADER_LEN = 28  # VFCT_IMAGE_HEADER


def parse(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < IMAGE_HEADER_OFF:
        raise ValueError("file is too small to be a VFCT table")
    if data[0:4] != b"VFCT":
        raise ValueError("missing VFCT signature")
    (table_len,) = struct.unpack_from("<I", data, 4)
    (vbios_offset,) = struct.unpack_from("<I", data, ACPI_HEADER_LEN + 16)
    end = min(table_len, len(data))
    if not IMAGE_HEADER_OFF <= vbios_offset <= end:
        raise ValueError(f"invalid VBIOS image offset: {vbios_offset:#x}")

    images = []
    off = vbios_offset
    while off + IMAGE_HEADER_LEN <= end:
        (pci_bus, pci_dev, pci_fn, vendor, device,
         _ssvid, _ssid, _rev, image_len) = struct.unpack_from("<IIIHHHHII", data, off)
        if not image_len:
            break
        content = data[off + IMAGE_HEADER_LEN:off + IMAGE_HEADER_LEN + image_len]
        if len(content) != image_len:
            raise ValueError("truncated VBIOS image")
        images.append({
            "bus": pci_bus, "dev": pci_dev, "fn": pci_fn,
            "vendor": vendor, "device": device,
            "content": content,
        })
        off += IMAGE_HEADER_LEN + image_len
    return images


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--file", default=DEFAULT_TABLE, help=f"VFCT table (default: {DEFAULT_TABLE})")
    ap.add_argument("--output-dir", default=".", help="where to write the images (default: .)")
    ap.add_argument("--list", action="store_true", help="list images without writing them")
    args = ap.parse_args()

    try:
        images = parse(args.file)
    except OSError as exc:
        print(f"error: cannot read {args.file}: {exc}", file=sys.stderr)
        return 2
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if not images:
        print("error: the VFCT table contains no VBIOS image", file=sys.stderr)
        return 1

    for img in images:
        bdf = f"{img['bus']:04x}:{img['dev']:02x}:{img['fn']:02x}.0"
        name = f"vbios_{img['vendor']:04x}_{img['device']:04x}.bin"
        if args.list:
            print(f"{name}  {len(img['content'])} bytes  (PCI {bdf})")
            continue
        os.makedirs(args.output_dir, exist_ok=True)
        path = os.path.join(args.output_dir, name)
        with open(path, "wb") as fh:
            fh.write(img["content"])
        print(f"{path}  {len(img['content'])} bytes  (PCI {bdf})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
