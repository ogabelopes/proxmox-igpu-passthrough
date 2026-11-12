#!/usr/bin/env bats
# Fixture-based tests for scripts/check-passthrough.sh and scripts/extract-vfct.py.
#
# The script reads /etc/pve, /proc, /sys and /dev; --root redirects those to the
# fixture tree, and the stub commands below replace lspci/lsmod/qm/dmidecode.

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"
  BIN="$BATS_TEST_TMPDIR/bin"

  mkdir -p "$ROOT/etc/pve/qemu-server" "$ROOT/etc/modprobe.d" "$ROOT/proc" "$ROOT/dev" \
    "$ROOT/usr/share/kvm" "$ROOT/sys/kernel/iommu_groups/17/devices" \
    "$ROOT/sys/bus/pci/devices/0000:05:00.0" "$ROOT/sys/bus/pci/devices/0000:05:00.1" \
    "$ROOT/sys/bus/pci/devices/0000:05:00.6" "$BIN"

  cat > "$ROOT/etc/pve/qemu-server/100.conf" <<'EOF'
bios: ovmf
machine: pc-q35-9.2
args: -cpu 'host,-hypervisor,kvm=off'
hostpci0: 0000:05:00.0,pcie=1,romfile=vbios.bin,x-vga=1
hostpci1: 0000:05:00.1,pcie=1,romfile=AMDGopDriver.rom
vga: std
ostype: win11
memory: 16384
name: win11
EOF
  : > "$ROOT/usr/share/kvm/vbios.bin"
  : > "$ROOT/usr/share/kvm/AMDGopDriver.rom"

  printf 'vfio\nvfio_iommu_type1\nvfio_pci\n' > "$ROOT/etc/modules"
  printf 'options vfio-pci ids=1002:1681,1002:1640 disable_vga=1\nsoftdep amdgpu pre: vfio-pci\n' \
    > "$ROOT/etc/modprobe.d/vfio.conf"

  printf 'BOOT_IMAGE=/boot/vmlinuz root=/dev/pve/root ro quiet amd_iommu=on iommu=pt initcall_blacklist=sysfb_init video=efifb:off\n' \
    > "$ROOT/proc/cmdline"
  printf 'MemTotal:       67108864 kB\n' > "$ROOT/proc/meminfo"
  printf 'model name\t: AMD Ryzen 9 6900HX with Radeon Graphics\n' > "$ROOT/proc/cpuinfo"
  printf 'bus\n' > "$ROOT/sys/bus/pci/devices/0000:05:00.0/reset_method"
  ln -s ../../../../kernel/iommu_groups/17 "$ROOT/sys/bus/pci/devices/0000:05:00.0/iommu_group"
  mkdir -p "$ROOT/sys/kernel/iommu_groups/17/devices/0000:05:00.0"

  cat > "$BIN/lspci" <<'EOF'
#!/bin/sh
case "$*" in
  "-Dn") printf '0000:05:00.0 0300: 1002:1681\n0000:05:00.1 0403: 1002:1640\n0000:05:00.6 0403: 1022:15e3\n' ;;
  "-Dn -s 0000:05:00.0") echo '0000:05:00.0 0300: 1002:1681' ;;
  "-Dn -s 0000:05:00.1") echo '0000:05:00.1 0403: 1002:1640' ;;
  "-Dn -s 0000:05:00.6") echo '0000:05:00.6 0403: 1022:15e3' ;;
  "-Dk -s 0000:05:00.0" | "-Dk -s 0000:05:00.1") printf 'Kernel driver in use: vfio-pci\n' ;;
  "-Dvvv -s 0000:05:00.0") printf 'FLReset-\n' ;;
  "-Dnn -s 0000:05:00.0") echo '0000:05:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt [Radeon 680M] [1002:1681] (rev c7)' ;;
  *) : ;;
esac
EOF
  cat > "$BIN/lsmod" <<'EOF'
#!/bin/sh
printf 'vfio_pci 123 0\namdgpu 123 0\n'
EOF
  cat > "$BIN/qm" <<'EOF'
#!/bin/sh
case "$1" in
  list) printf '      VMID NAME STATUS MEM(MB) BOOTDISK(GB) PID\n       100 win11 running 16384 512 1\n' ;;
  config) printf 'memory: 16384\n' ;;
  agent) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  cat > "$BIN/pveversion" <<'EOF'
#!/bin/sh
echo 'pve-manager/8.4.21/test'
EOF
  cat > "$BIN/qemu-system-x86_64" <<'EOF'
#!/bin/sh
echo 'QEMU emulator version 9.2.0'
EOF
  cat > "$BIN/dmidecode" <<'EOF'
#!/bin/sh
case "$2" in
  system-manufacturer) echo AZW ;;
  system-product-name) echo EQ ;;
esac
EOF
  chmod +x "$BIN"/*

  export PATH="$BIN:$PATH"
  export CHECK_PASSTHROUGH_ALLOW_NONROOT=1
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-passthrough.sh"
}

@test "healthy fixture reports OK" {
  run "$SCRIPT" --root "$ROOT" --json --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *'"result":"OK"'* ]]
  [[ "$output" != *'"level":"FAIL"'* ]]
}

@test "vga: none on a Windows guest fails VM-6" {
  sed -i 's/^vga: std/vga: none/' "$ROOT/etc/pve/qemu-server/100.conf"
  run "$SCRIPT" --root "$ROOT" --json --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *'"level":"FAIL","id":"VM-6"'* ]]
}

@test "nomodeset fails RBT-1" {
  printf ' quiet nomodeset' >> "$ROOT/proc/cmdline"
  run "$SCRIPT" --root "$ROOT" --json --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *'"level":"FAIL","id":"RBT-1"'* ]]
}

@test "memory oversubscription warns MEM-4 without failing" {
  printf 'MemTotal:       4194304 kB\n' > "$ROOT/proc/meminfo"
  run "$SCRIPT" --root "$ROOT" --json --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *'"level":"WARN","id":"MEM-4"'* ]]
}

@test "--explain prints why/fix for the warning" {
  run "$SCRIPT" --root "$ROOT" --vmid 100 --explain
  [ "$status" -eq 0 ]
  [[ "$output" == *"why:"* ]]
  [[ "$output" == *"fix:"* ]]
}

@test "--matrix-row prints a sanitized row" {
  run "$SCRIPT" --root "$ROOT" --vmid 100 --matrix-row
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ryzen 9 6900HX"* ]]
  [[ "$output" == *"1002:1681"* ]]
  [[ "$output" == *"GPU + audio"* ]]
}

@test "extract-vfct writes the VBIOS image" {
  local table="$BATS_TEST_TMPDIR/VFCT"
  python3 - "$table" <<'PY'
import struct, sys
img = b'\x55\xaa' + b'\x00' * 22
hdr = bytearray(76)
hdr[0:4] = b'VFCT'
struct.pack_into('<I', hdr, 4, 76 + 28 + len(img))
struct.pack_into('<I', hdr, 52, 76)
imgh = struct.pack('<IIIHHHHII', 5, 0, 0, 0x1002, 0x1681, 0, 0, 0, len(img))
open(sys.argv[1], 'wb').write(bytes(hdr) + imgh + img)
PY
  run python3 "$BATS_TEST_DIRNAME/../scripts/extract-vfct.py" --file "$table" --output-dir "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/out/vbios_1002_1681.bin" ]
  [ "$(wc -c < "$BATS_TEST_TMPDIR/out/vbios_1002_1681.bin")" -eq 24 ]
}

@test "--commands prints a fix command for a failure" {
  sed -i 's/^vga: std/vga: none/' "$ROOT/etc/pve/qemu-server/100.conf"
  run "$SCRIPT" --root "$ROOT" --vmid 100 --commands
  [ "$status" -eq 1 ]
  [[ "$output" == *"qm set <VMID> --vga std"* ]]
}
