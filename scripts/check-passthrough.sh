#!/usr/bin/env bash
# check-passthrough.sh -- read-only sanity check for a Proxmox VE PCI passthrough.
#
# Usage:
#   sudo ./scripts/check-passthrough.sh [VMID] [options]
#
# Options:
#   -v, --vmid ID     check a specific VM (default: every VM with hostpci)
#       --guest       also inspect the Windows guest via the QEMU guest agent
#       --matrix-row  print a sanitized hardware-matrix row and exit
#   -e, --explain     print why/fix for every warning and failure
#   -w, --watch       refresh the report every 2s (Ctrl-C to stop)
#       --commands    print only suggested fix commands
#       --root DIR    read files under DIR instead of / (testing)
#       --json        machine-readable summary on stdout
#   -q, --quiet       exit code only (suppresses the human report)
#   -h, --help        this help
#   -V, --version     script version
#
# Read-only: it inspects /etc/pve, /sys and /proc and changes nothing.
# Exit status: 0 = no failures, 1 = at least one FAIL, 2 = usage/permission error.
set -u

VERSION="1.0.0"

PASS=0
WARN=0
FAIL=0
RESULTS=()
JSON=0
QUIET=0
GUEST=0
MATRIX=0
EXPLAIN=0
WATCH=0
COMMANDS=0
VMID=""
ROOT=""

declare -A WHY=()
declare -A FIX=()
declare -A CMD=()

use_color=0
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then use_color=1; fi
c_ok=$'\033[32m'
c_warn=$'\033[33m'
c_fail=$'\033[31m'
c_info=$'\033[36m'
c_reset=$'\033[0m'

label() {
  case "$1" in
    PASS) printf '%s[PASS]%s' "$c_ok" "$c_reset" ;;
    WARN) printf '%s[WARN]%s' "$c_warn" "$c_reset" ;;
    FAIL) printf '%s[FAIL]%s' "$c_fail" "$c_reset" ;;
    info) printf '%s[info]%s' "$c_info" "$c_reset" ;;
  esac
}

explain() {
  WHY[$1]=$2
  FIX[$1]=$3
}

cmd() { CMD[$1]=$2; }

usage() {
  cat <<'EOF'
Usage: sudo ./check-passthrough.sh [VMID] [options]

Options:
  -v, --vmid ID     check a specific VM (default: every VM with hostpci)
      --guest       also inspect the Windows guest via the QEMU guest agent
      --matrix-row  print a sanitized hardware-matrix row and exit
  -e, --explain     print why/fix for every warning and failure
  -w, --watch       refresh the report every 2s (Ctrl-C to stop)
      --commands    print only suggested fix commands
      --root DIR    read files under DIR instead of / (testing)
      --json        machine-readable summary on stdout
  -q, --quiet       exit code only (suppresses the human report)
  -h, --help        this help
  -V, --version     script version

Read-only: it inspects /etc/pve, /sys and /proc and changes nothing.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -V | --version) printf 'check-passthrough %s\n' "$VERSION"; exit 0 ;;
    -v | --vmid)
      [ $# -ge 2 ] || die "--vmid needs an argument"
      VMID="$2"
      shift 2
      ;;
    --guest) GUEST=1; shift ;;
    --matrix-row) MATRIX=1; shift ;;
    -e | --explain) EXPLAIN=1; shift ;;
    -w | --watch) WATCH=1; shift ;;
    --commands) COMMANDS=1; shift ;;
    --root)
      [ $# -ge 2 ] || die "--root needs an argument"
      ROOT="${2%/}"
      shift 2
      ;;
    --json) JSON=1; shift ;;
    -q | --quiet) QUIET=1; shift ;;
    -*)
      die "unknown option: $1 (try --help)"
      ;;
    *)
      if [ -n "$VMID" ]; then
        die "unexpected argument: $1"
      fi
      [[ "$1" =~ ^[0-9]+$ ]] || die "VMID must be numeric: $1"
      VMID="$1"
      shift
      ;;
  esac
done

if [ "$WATCH" -eq 1 ] && { [ "$JSON" -eq 1 ] || [ "$QUIET" -eq 1 ] || [ "$COMMANDS" -eq 1 ] || [ "$MATRIX" -eq 1 ]; }; then
  die "--watch cannot be combined with --json, --quiet, --commands or --matrix-row"
fi
if [ "$COMMANDS" -eq 1 ] && [ "$JSON" -eq 1 ]; then
  die "--commands cannot be combined with --json"
fi
if [ "$COMMANDS" -eq 1 ]; then
  QUIET=1
fi

if [ "$WATCH" -eq 1 ]; then
  [ -f "$0" ] || die "--watch requires running the script from a file"
  watch_args=( "$0" )
  [ -n "$ROOT" ] && watch_args+=( --root "$ROOT" )
  [ -n "$VMID" ] && watch_args+=( --vmid "$VMID" )
  [ "$GUEST" -eq 1 ] && watch_args+=( --guest )
  [ "$EXPLAIN" -eq 1 ] && watch_args+=( --explain )
  while :; do
    if [ -t 1 ]; then
      printf '\033[2J\033[H'
    else
      printf '\n--- refresh %s ---\n' "$(date +%T)"
    fi
    "${watch_args[@]}" || true
    printf '\n[watch] refreshing every 2s; Ctrl-C to stop\n'
    sleep 2
  done
fi

emit() { [ "$QUIET" -eq 1 ] && return 0; printf '%s\n' "$*"; }
line() {
  if [ "$QUIET" -eq 1 ]; then return 0; fi
  if [ "$use_color" -eq 1 ]; then emit "  $(label "$1") $2  $3"; else emit "  [$1] $2  $3"; fi
}
ok() { PASS=$((PASS + 1)); RESULTS+=("PASS|$1|$2"); line PASS "$1" "$2"; }
warn() { WARN=$((WARN + 1)); RESULTS+=("WARN|$1|$2"); line WARN "$1" "$2"; }
fail() { FAIL=$((FAIL + 1)); RESULTS+=("FAIL|$1|$2"); line FAIL "$1" "$2"; }
info() { RESULTS+=("INFO|$1|$2"); line info "$1" "$2"; }
section() { emit ""; emit "== $* =="; }

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

print_json() {
  local first=1 r level id msg why fix result
  if [ "$FAIL" -gt 0 ]; then result="FAIL"; else result="OK"; fi
  printf '{"version":"%s","pass":%d,"warn":%d,"fail":%d,"result":"%s","checks":[' \
    "$VERSION" "$PASS" "$WARN" "$FAIL" "$result"
  for r in "${RESULTS[@]}"; do
    level=${r%%|*}
    r=${r#*|}
    id=${r%%|*}
    msg=${r#*|}
    why=${WHY[$id]:-}
    fix=${FIX[$id]:-}
    command=${CMD[$id]:-}
    if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
    printf '{"level":"%s","id":"%s","message":"%s","why":"%s","fix":"%s","command":"%s"}' \
      "$level" "$(json_escape "$id")" "$(json_escape "$msg")" \
      "$(json_escape "$why")" "$(json_escape "$fix")" "$(json_escape "$command")"
  done
  printf ']}\n'
}

print_explanations() {
  local r level id seen=" "
  emit ""
  emit "== Explanations =="
  for r in "${RESULTS[@]}"; do
    level=${r%%|*}
    case "$level" in
      PASS | INFO) continue ;;
    esac
    r=${r#*|}
    id=${r%%|*}
    case "$seen" in
      *" $id "*) continue ;;
    esac
    seen="$seen$id "
    emit "  $id"
    emit "    why: ${WHY[$id]:-no description}"
    emit "    fix: ${FIX[$id]:-no suggested fix}"
  done
}

print_commands() {
  local r level id msg seen=" "
  printf '# check-passthrough %s -- suggested fixes (review before running)\n' "$VERSION"
  for r in "${RESULTS[@]}"; do
    level=${r%%|*}
    case "$level" in PASS | INFO) continue ;; esac
    r=${r#*|}
    id=${r%%|*}
    msg=${r#*|}
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    printf '\n# %s %s: %s\n' "$level" "$id" "$msg"
    if [ -n "${CMD[$id]:-}" ]; then
      printf '%s\n' "${CMD[$id]}"
    else
      printf '# (no command; see --explain)\n'
    fi
  done
}

require_root() {
  if [ "${CHECK_PASSTHROUGH_ALLOW_NONROOT:-0}" != "1" ]; then
    [ "$(id -u)" -eq 0 ] || die "run as root"
  fi
  [ -d "$ROOT/etc/pve" ] || die "this does not look like a Proxmox VE node (/etc/pve is missing)"
}

# Run a read-only PowerShell expression inside the guest and print its output.
guest_ps() {
  local expr=$1 out
  out=$(timeout 30 qm guest exec "$VMID" -- powershell.exe -NoProfile -NonInteractive \
    -Command "$expr" 2>/dev/null) || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
txt = (d.get("out-data") or "").strip()
if not txt and d.get("err-data"):
    txt = d["err-data"].strip()
print(txt)
'
}

toggle_gpu() {
  # Print the GPU + audio binding summary, used by --matrix-row.
  local bdf=$1 vendor slot fbdf fclass fvendor drv found="no"
  vendor=$(lspci -Dn -s "$bdf" | awk '{print $3}' | cut -d: -f1)
  slot=${bdf%.*}
  for fn in "$ROOT/sys/bus/pci/devices/$slot".*; do
    [ -e "$fn" ] || continue
    fbdf=${fn##*/}
    fclass=$(lspci -Dn -s "$fbdf" | awk '{print $2}')
    fvendor=$(lspci -Dn -s "$fbdf" | awk '{print $3}' | cut -d: -f1)
    if [ "$fclass" = "0403:" ] && [ "$fvendor" = "$vendor" ]; then
      drv=$(lspci -Dk -s "$fbdf" | sed -n 's/.*Kernel driver in use: //p')
      if [ "$drv" = "vfio-pci" ]; then found="yes"; fi
    fi
  done
  if [ "$found" = "yes" ]; then
    printf 'GPU + audio'
  else
    printf 'GPU only'
  fi
}

matrix_row() {
  require_root
  command -v dmidecode >/dev/null || die "dmidecode is required for --matrix-row"
  local cpu bdf gpu_line gpu_id gpu_name vendor product pve kernel qemu guest binding ostype
  cpu=$(awk -F': ' '/^model name/{print $2; exit}' "$ROOT/proc/cpuinfo")
  bdf=$(lspci -Dn | awk '$2 ~ /^(0300|0302|0380):/ {print $1; exit}')
  [ -n "$bdf" ] || die "no display-class device found"
  gpu_line=$(lspci -Dnn -s "$bdf")
  gpu_id=$(printf '%s' "$gpu_line" | grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]' | tail -n 1 | tr -d '[]')
  gpu_name=$(printf '%s' "$gpu_line" | sed -E 's/^[^ ]+ [^:]+: (.*) \[[0-9a-f]{4}:[0-9a-f]{4}\].*/\1/')
  vendor=$(dmidecode -s system-manufacturer 2>/dev/null)
  product=$(dmidecode -s system-product-name 2>/dev/null)
  pve=$(pveversion 2>/dev/null | sed -n 's|^pve-manager/\([^/]*\)/.*|\1|p')
  kernel=$(uname -r)
  qemu=$(qemu-system-x86_64 --version 2>/dev/null | head -n 1 | awk '{print $4}')
  binding=$(toggle_gpu "$bdf")
  guest="Windows 11"
  if [ -n "$VMID" ] && [ -f "$ROOT/etc/pve/qemu-server/$VMID.conf" ]; then
    ostype=$(sed -n 's/^ostype: //p' "$ROOT/etc/pve/qemu-server/$VMID.conf")
    case "$ostype" in
      win11) guest="Windows 11" ;;
      win10) guest="Windows 10" ;;
      l26) guest="Linux" ;;
      "") : ;;
      *) guest="$ostype" ;;
    esac
  fi
  printf '<!-- edit the machine column to the retail model name -->\n'
  printf '| %s | %s \140%s\140 | %s %s | %s · %s · %s | %s | %s | TBD | %s |\n' \
    "$cpu" "$gpu_name" "$gpu_id" "$vendor" "$product" \
    "${pve:-?}" "$kernel" "${qemu:-?}" "$guest" "$binding" "$(date +%Y-%m)"
}

explain IOMMU-1 \
  "IOMMU groups are what allow the kernel to isolate a device for assignment to a VM." \
  "Enable IOMMU/AMD-Vi in firmware, add iommu=pt (and amd_iommu=on) to the kernel cmdline, reboot."
explain IOMMU-2 \
  "iommu=pt keeps the host's DMA paths in pass-through mode and is required for stable assignment." \
  "Add iommu=pt to GRUB_CMDLINE_LINUX_DEFAULT, run update-grub, reboot."
explain IOMMU-3 \
  "The IOMMU is usually enabled by firmware, but the cmdline makes the setting explicit." \
  "Add amd_iommu=on to the kernel cmdline if the groups are missing."
explain VFIO-1 \
  "Without vfio-pci loaded, the device cannot be handed to QEMU." \
  "Load vfio_pci (and vfio_iommu_type1) at boot via /etc/modules, then update-initramfs."
explain VFIO-2 \
  "The vfio modules must load at boot, before the native GPU driver." \
  "Add vfio, vfio_iommu_type1 and vfio_pci to /etc/modules."
explain VFIO-3 \
  "The device IDs tell vfio-pci which functions to claim before amdgpu/radeon see them." \
  "Add 'options vfio-pci ids=<gpu>,<audio> disable_vga=1' to /etc/modprobe.d/vfio.conf."
explain VFIO-4 \
  "Softdeps guarantee vfio-pci probes the GPU before the native driver can bind it." \
  "Add 'softdep amdgpu pre: vfio-pci' (and radeon/snd_hda_intel) to vfio.conf."
explain DEV-1 \
  "A display function owned by the host cannot be passed through." \
  "Fix the vfio-pci IDs/softdeps and reboot; confirm with 'lspci -k'."
explain DEV-5 \
  "The GPU's HD-audio function must follow the GPU, or Windows reports Error 43 / no audio." \
  "Add the audio function ID to vfio-pci ids and pass it as a second hostpci entry."
explain RBT-1 \
  "nomodeset sets drm_firmware_drivers_only(); amdgpu_init() then returns EINVAL and the module cannot load." \
  "Remove nomodeset; use initcall_blacklist=sysfb_init video=efifb:off instead."
explain RBT-2 \
  "sysfb_init would otherwise let the EFI framebuffer claim the GPU aperture, breaking a host amdgpu bind." \
  "Add initcall_blacklist=sysfb_init video=efifb:off to the kernel cmdline."
explain RBT-3 \
  "A blacklisted amdgpu can never be rebound to the GPU, so the host-side reset hook cannot work." \
  "Remove 'blacklist amdgpu' if you want the host to be able to reclaim the GPU between runs."
explain VM-1 \
  "A virtual display can fight the passthrough, and it is required by the reset service." \
  "Use vga: std when you rely on RadeonResetBugFix; vga: none only without the service."
explain VM-2 \
  "OVMF is what the passthrough and the AMD GOP ROM path expect." \
  "Set bios: ovmf in the VM config."
explain VM-3 \
  "q35 is the machine type the passthrough and OVMF configuration target." \
  "Set machine: pc-q35-<version>."
explain VM-4 \
  "pcie=1 presents the device as a PCIe endpoint, which the GPU's BARs expect." \
  "Add pcie=1 to the hostpci line."
explain VM-5 \
  "Without -hypervisor the guest can detect the hypervisor; AMD drivers may refuse to start." \
  "Add '-cpu host,-hypervisor,kvm=off' to args."
explain VM-6 \
  "RadeonResetBugFix cannot disable the only display adapter; a Windows shutdown then hangs." \
  "Add a virtual GPU: qm set <vmid> --vga std."
explain VM-7 \
  "-no-reboot makes a guest restart exit QEMU, so the reset service never runs its cycle." \
  "Remove -no-reboot from args if you rely on the service."
explain VM-8 \
  "The Radeon should be the primary display; otherwise Windows may render on the virtual adapter." \
  "Add x-vga=1 to the GPU hostpci line."
explain VM-9 \
  "The guest firmware needs the GPU's option ROM to post the display." \
  "Restore the ROM file to /usr/share/kvm (it is in the pve-host backup)."
explain VM-10 \
  "A referenced ROM file is missing, so QEMU cannot start or the display will not post." \
  "Restore the file to /usr/share/kvm or fix the romfile= path."
explain MEM-3 \
  "VM allocations must leave the hypervisor enough memory to run." \
  "Lower the VM memory or set a balloon floor so the host keeps headroom."
explain MEM-4 \
  "Starting another VM here can trigger an OOM kill; a killed QEMU can leave the GPU wedged." \
  "Reduce memory/balloon, or stop another VM before starting this one."
explain CON-2 \
  "Expected when the framebuffer is blacklisted for passthrough; recovery is GRUB or a live USB." \
  "No action needed if you do not need a host console."
explain GST-2 \
  "The guest-side service is what makes reboots survive the AMD reset bug." \
  "Install and start RadeonResetBugFix in the guest."
explain GST-3 \
  "The service must start automatically so the GPU is re-enabled on every boot." \
  "Set the RadeonResetBugFix service to Automatic."
explain GST-4 \
  "Hybrid shutdown leaves the GPU half-initialised and defeats the adapter handoff." \
  "Run 'powercfg /h off' in the guest."
explain GST-6 \
  "Guest-side checks need the QEMU guest agent." \
  "Install the VirtIO guest tools in the guest."

cmd IOMMU-1 '# enable IOMMU/AMD-Vi in firmware, then add iommu=pt to /etc/default/grub and reboot'
cmd IOMMU-2 'sed -i "s/quiet/quiet iommu=pt/" /etc/default/grub && update-grub && reboot'
cmd IOMMU-3 'sed -i "s/quiet/quiet amd_iommu=on/" /etc/default/grub && update-grub && reboot'
cmd VFIO-1 '# load vfio_pci at boot (see VFIO-2)'
cmd VFIO-2 "printf 'vfio\\nvfio_iommu_type1\\nvfio_pci\\n' >> /etc/modules && update-initramfs -u -k all"
cmd VFIO-3 "echo 'options vfio-pci ids=<GPU_ID>,<AUDIO_ID> disable_vga=1' >> /etc/modprobe.d/vfio.conf"
cmd VFIO-4 "printf 'softdep amdgpu pre: vfio-pci\\n' >> /etc/modprobe.d/vfio.conf"
cmd DEV-5 '# add the audio ID to vfio-pci ids and pass it as hostpci1'
cmd RBT-1 'sed -i "s/ nomodeset//; s/ video=amdgpu:off//" /etc/default/grub && update-grub && update-initramfs -u -k all && reboot'
cmd RBT-2 'sed -i "s/quiet/quiet initcall_blacklist=sysfb_init video=efifb:off/" /etc/default/grub && update-grub && reboot'
cmd RBT-3 'sed -i "s/^blacklist amdgpu/# blacklist amdgpu/" /etc/modprobe.d/blacklist.conf'
cmd VM-1 'qm set <VMID> --vga std'
cmd VM-2 'qm set <VMID> --bios ovmf'
cmd VM-3 'qm set <VMID> --machine q35'
cmd VM-4 'qm set <VMID> --hostpci0 <BDF>,pcie=1,romfile=<ROM>,x-vga=1'
cmd VM-5 "qm set <VMID> --args \"-cpu 'host,-hypervisor,kvm=off'\""
cmd VM-6 'qm set <VMID> --vga std'
cmd VM-7 "qm set <VMID> --args \"-cpu 'host,-hypervisor,kvm=off'\""
cmd VM-8 'qm set <VMID> --hostpci0 <BDF>,pcie=1,romfile=<ROM>,x-vga=1'
cmd VM-10 '# restore the ROM to /usr/share/kvm/<ROM>'
cmd MEM-4 'qm set <VMID> --memory <SMALLER>   # or stop another VM first'
cmd CON-2 '# no action needed if you do not need a host console'
cmd GST-2 '# in the guest: RadeonResetBugFixService.exe install'
cmd GST-3 '# in the guest: sc config RadeonResetBugFix start= auto'
cmd GST-4 '# in the guest: powercfg /h off'
cmd GST-6 '# install the VirtIO guest tools in the guest'

require_root

if [ "$MATRIX" -eq 1 ]; then
  matrix_row
  exit 0
fi

if [ "$GUEST" -eq 1 ] && [ -z "$VMID" ]; then
  die "--guest requires --vmid"
fi

cmdline=$(cat "$ROOT/proc/cmdline" 2>/dev/null || true)

emit ""
emit "check-passthrough $VERSION"

section "Host"
info HOST-1 "script  $VERSION"
info HOST-2 "kernel  $(uname -r)"
pve=$(pveversion 2>/dev/null | sed -n 's|^pve-manager/\([^/]*\)/.*|\1|p')
[ -n "$pve" ] && info HOST-3 "proxmox $pve"
qemu=$(qemu-system-x86_64 --version 2>/dev/null | head -n 1 | awk '{print $4}')
[ -n "$qemu" ] && info HOST-4 "qemu    $qemu"

section "IOMMU"
groups=0
[ -d "$ROOT/sys/kernel/iommu_groups" ] && groups=$(find "$ROOT/sys/kernel/iommu_groups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
if [ "$groups" -gt 0 ]; then
  ok IOMMU-1 "IOMMU groups present ($groups groups)"
else
  fail IOMMU-1 "no IOMMU groups present"
fi
case " $cmdline " in
  *" iommu=pt "*) ok IOMMU-2 "kernel cmdline has iommu=pt" ;;
  *) warn IOMMU-2 "kernel cmdline has no iommu=pt" ;;
esac
case " $cmdline " in
  *" amd_iommu=on "* | *" intel_iommu=on "*) ok IOMMU-3 "kernel cmdline explicitly enables the IOMMU" ;;
  *) warn IOMMU-3 "no amd_iommu=on / intel_iommu=on on the cmdline" ;;
esac

section "vfio-pci"
if lsmod | grep -q '^vfio_pci '; then
  ok VFIO-1 "vfio_pci is loaded"
else
  fail VFIO-1 "vfio_pci is not loaded"
fi
if grep -qsE '^[^#]*vfio' "$ROOT/etc/modules"; then
  ok VFIO-2 "/etc/modules loads the vfio modules"
else
  warn VFIO-2 "/etc/modules has no vfio entries"
fi
vfio_opts=$(grep -hsE '^[[:space:]]*options[[:space:]]+vfio-pci' "$ROOT"/etc/modprobe.d/*.conf 2>/dev/null || true)
if [ -n "$vfio_opts" ]; then
  ok VFIO-3 "vfio-pci options configured"
  emit "$(printf '%s\n' "$vfio_opts" | sed 's/^/         /')"
else
  fail VFIO-3 "no 'options vfio-pci ids=...' in /etc/modprobe.d"
fi
if grep -qsE '^[[:space:]]*softdep[[:space:]]+(amdgpu|radeon|snd_hda_intel)[[:space:]]+pre' "$ROOT"/etc/modprobe.d/*.conf 2>/dev/null; then
  ok VFIO-4 "softdep keeps the native GPU/audio drivers from loading first"
else
  warn VFIO-4 "no softdep lines for the native GPU/audio drivers"
fi

section "Display devices"
mapfile -t gpus < <(lspci -Dn | awk '$2 ~ /^(0300|0302|0380):/ {print $1}')
if [ "${#gpus[@]}" -eq 0 ]; then
  fail DEV-0 "no display-class PCI device found"
fi
for bdf in "${gpus[@]}"; do
  desc=$(lspci -Dn -s "$bdf")
  drv=$(lspci -Dk -s "$bdf" | sed -n 's/.*Kernel driver in use: //p')
  if [ "$drv" = "vfio-pci" ]; then
    ok DEV-1 "$desc -> vfio-pci"
  else
    warn DEV-1 "$desc -> ${drv:-no driver} (not bound to vfio-pci)"
  fi
  if [ -e "$ROOT/sys/bus/pci/devices/$bdf/iommu_group" ]; then
    grp_path=$(readlink -f "$ROOT/sys/bus/pci/devices/$bdf/iommu_group")
    grp=$(basename "$grp_path")
    members=$(find "$grp_path/devices" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
    info DEV-2 "IOMMU group $grp ($members device(s))"
    if [ "$members" -gt 1 ]; then
      info DEV-2 "  group members -- every one must be passed through or be reset-safe:"
      for d in "$grp_path"/devices/*; do
        emit "           $(lspci -Dn -s "${d##*/}")"
      done
    fi
  fi
  if [ -e "$ROOT/sys/bus/pci/devices/$bdf/reset_method" ]; then
    info DEV-3 "reset_method=$(cat "$ROOT/sys/bus/pci/devices/$bdf/reset_method")"
  fi
  flr=$(lspci -Dvvv -s "$bdf" 2>/dev/null | grep -o 'FLReset[+-]' | head -n 1)
  [ -n "$flr" ] && info DEV-4 "function-level reset: $flr"

  # The GPU's HD-audio function sits on the same slot and is the usual cause of
  # Error 43 / "no audio" when it is left with the host driver. The onboard HDA
  # codec can share that slot, so match on the display device's vendor first.
  gpu_vendor=$(lspci -Dn -s "$bdf" | awk '{print $3}' | cut -d: -f1)
  slot=${bdf%.*}
  for fn in "$ROOT/sys/bus/pci/devices/$slot".*; do
    [ -e "$fn" ] || continue
    fbdf=${fn##*/}
    fclass=$(lspci -Dn -s "$fbdf" | awk '{print $2}')
    case "$fclass" in
      0403:*)
        fvendor=$(lspci -Dn -s "$fbdf" | awk '{print $3}' | cut -d: -f1)
        if [ "$fvendor" != "$gpu_vendor" ]; then
          info DEV-6 "audio function $fbdf (vendor $fvendor) is the onboard codec, not the GPU's"
          continue
        fi
        adrv=$(lspci -Dk -s "$fbdf" | sed -n 's/.*Kernel driver in use: //p')
        if [ "$adrv" = "vfio-pci" ]; then
          ok DEV-5 "audio function $fbdf -> vfio-pci"
        else
          warn DEV-5 "audio function $fbdf -> ${adrv:-no driver} (pass it through too)"
        fi
        ;;
    esac
  done
done

section "Reboot readiness (host)"
case " $cmdline " in
  *" nomodeset "*) fail RBT-1 "nomodeset is on the cmdline; amdgpu cannot load" ;;
  *) ok RBT-1 "nomodeset is not set (amdgpu may load)" ;;
esac
case " $cmdline " in
  *" initcall_blacklist=sysfb_init "*) ok RBT-2 "sysfb_init is blacklisted (framebuffer does not claim the GPU aperture)" ;;
  *) warn RBT-2 "sysfb_init is not blacklisted (the EFI framebuffer may hold the GPU aperture)" ;;
esac
if grep -qsE '^[[:space:]]*blacklist[[:space:]]+amdgpu' "$ROOT"/etc/modprobe.d/*.conf 2>/dev/null; then
  warn RBT-3 "amdgpu is blacklisted -- a host-side rebind hook cannot initialize the GPU"
else
  ok RBT-3 "amdgpu is not blacklisted"
fi
if lsmod | grep -q '^amdgpu '; then
  info RBT-4 "amdgpu module is loaded"
else
  info RBT-4 "amdgpu module is not loaded"
fi

section "VM configuration"
shopt -s nullglob
if [ -n "$VMID" ]; then
  confs=("$ROOT/etc/pve/qemu-server/$VMID.conf")
else
  confs=("$ROOT"/etc/pve/qemu-server/*.conf)
fi
if [ "${#confs[@]}" -eq 0 ] || [ ! -e "${confs[0]}" ]; then
  warn VM-0 "no matching VM config found"
fi
for f in "${confs[@]}"; do
  [ -f "$f" ] || continue
  grep -q '^hostpci' "$f" || continue
  id=$(basename "$f" .conf)
  vname=$(sed -n 's/^name: //p' "$f")
  emit "  VM $id (${vname:-unnamed})"

  if grep -qE '^vga:[[:space:]]*none' "$f"; then
    warn VM-1 "vga: none (no virtual display)"
  else
    ok VM-1 "vga is not 'none' (virtual display present)"
  fi
  if grep -qE '^bios:[[:space:]]*ovmf' "$f"; then
    ok VM-2 "bios: ovmf"
  else
    warn VM-2 "bios is not ovmf"
  fi
  if grep -qE '^machine:.*q35' "$f"; then
    ok VM-3 "q35 machine"
  else
    warn VM-3 "machine is not q35"
  fi
  if grep -qE '^hostpci[0-9]+:.*pcie=1' "$f"; then
    ok VM-4 "hostpci uses pcie=1"
  else
    warn VM-4 "no hostpci line with pcie=1"
  fi
  if grep -qE '^args:.*-hypervisor' "$f"; then
    ok VM-5 "args hide the hypervisor (-hypervisor)"
  else
    warn VM-5 "no '-hypervisor' in args"
  fi

  ostype=$(sed -n 's/^ostype: //p' "$f")
  if [[ "$ostype" == win* ]]; then
    if grep -qE '^vga:[[:space:]]*none' "$f"; then
      fail VM-6 "Windows guest with vga: none (the reset service cannot disable the only GPU)"
    else
      ok VM-6 "Windows guest has a virtual GPU (required by RadeonResetBugFix)"
    fi
    if grep -qE '^args:.*-no-reboot' "$f"; then
      warn VM-7 "-no-reboot in args (an in-place restart cannot run the service cycle)"
    else
      ok VM-7 "no -no-reboot in args"
    fi
    if grep -qE '^hostpci[0-9]+:.*x-vga=1' "$f"; then
      ok VM-8 "Radeon is the primary display (x-vga=1)"
    else
      warn VM-8 "no x-vga=1 (the Radeon may not be the primary display)"
    fi
  fi

  while IFS= read -r rom; do
    [ -n "$rom" ] || continue
    if [ -f "$ROOT/usr/share/kvm/$rom" ]; then
      ok VM-9 "romfile $rom present in /usr/share/kvm"
    else
      fail VM-10 "romfile $rom is referenced but missing from /usr/share/kvm"
    fi
  done < <(grep -hoE 'romfile=[^,]+' "$f" | sed 's/^romfile=//')
done

section "Memory"
if command -v qm >/dev/null; then
  mem_total=$(awk '/^MemTotal:/{printf "%d", $2/1024}' "$ROOT/proc/meminfo")
  vm_sum=0
  while read -r id; do
    [ -n "$id" ] || continue
    m=$(qm config "$id" 2>/dev/null | awk -F': ' '/^memory:/{print $2}')
    case "$m" in '' | *[!0-9]*) m=0 ;; esac
    vm_sum=$((vm_sum + m))
  done < <(qm list 2>/dev/null | awk 'NR>1 && $3=="running"{print $1}')
  extra=0
  if [ -n "$VMID" ] && ! qm list 2>/dev/null | awk -v id="$VMID" 'NR>1 && $1==id && $3=="running"{found=1} END{exit !found}'; then
    m=$(qm config "$VMID" 2>/dev/null | awk -F': ' '/^memory:/{print $2}')
    case "$m" in '' | *[!0-9]*) m=0 ;; esac
    extra=$m
  fi
  info MEM-1 "running VMs request ${vm_sum} MiB of ${mem_total} MiB host RAM"
  [ "$extra" -gt 0 ] && info MEM-2 "starting VM $VMID would add ${extra} MiB"
  if [ $((vm_sum + extra)) -gt $((mem_total - 2048)) ]; then
    warn MEM-4 "VM memory exceeds host RAM minus 2 GiB (OOM risk)"
  else
    ok MEM-3 "VM memory fits with at least 2 GiB of host headroom"
  fi
else
  info MEM-1 "qm not found, skipping the memory check"
fi

section "Local console"
fb_count=0
[ -d "$ROOT/dev" ] && fb_count=$(find "$ROOT/dev" -maxdepth 1 -name 'fb*' 2>/dev/null | wc -l)
if [ "$fb_count" -gt 0 ]; then
  ok CON-1 "a framebuffer exists (/dev/fb*)"
else
  warn CON-2 "no /dev/fb* -- the host has no local console"
fi
case " $cmdline " in
  *nomodeset* | *"video="*) info CON-3 "cmdline restricts the framebuffer; recover via GRUB or a live USB" ;;
esac

if [ "$GUEST" -eq 1 ]; then
  ostype=$(sed -n 's/^ostype: //p' "$ROOT/etc/pve/qemu-server/$VMID.conf" 2>/dev/null || true)
  if [[ "$ostype" != win* ]]; then
    info GST-0 "guest-side checks are Windows-only; ostype is '${ostype:-unknown}'"
    GUEST=0
  fi
fi

if [ "$GUEST" -eq 1 ]; then
  section "Guest (agent)"
  if timeout 8 qm agent "$VMID" ping >/dev/null 2>&1; then
    ok GST-1 "QEMU guest agent responds"
    s_status=$(guest_ps '(Get-Service RadeonResetBugFix).Status') || s_status=""
    if [ "$s_status" = "Running" ]; then
      ok GST-2 "RadeonResetBugFix service is Running"
    elif [ -n "$s_status" ]; then
      fail GST-2 "RadeonResetBugFix service status: $s_status"
    else
      warn GST-2 "could not read the RadeonResetBugFix service state"
    fi
    s_start=$(guest_ps '(Get-Service RadeonResetBugFix).StartType') || s_start=""
    if [ "$s_start" = "Automatic" ]; then
      ok GST-3 "RadeonResetBugFix StartType is Automatic"
    elif [ -n "$s_start" ]; then
      warn GST-3 "RadeonResetBugFix StartType: $s_start (expected Automatic)"
    fi
    hiberboot=$(guest_ps "(Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power' -Name HiberbootEnabled).HiberbootEnabled") || hiberboot=""
    if [ "$hiberboot" = "0" ]; then
      ok GST-4 "Fast Startup is disabled (HiberbootEnabled=0)"
    elif [ -n "$hiberboot" ]; then
      warn GST-4 "Fast Startup is enabled (HiberbootEnabled=$hiberboot)"
    else
      warn GST-4 "could not read HiberbootEnabled"
    fi
    displays=$(guest_ps '(Get-PnpDevice -Class Display -Status OK).FriendlyName') || displays=""
    if [ -n "$displays" ]; then
      info GST-5 "active display adapters:"
      printf '%s\n' "$displays" | while IFS= read -r line; do [ -n "$line" ] && emit "           $line"; done
    else
      warn GST-5 "could not list display adapters"
    fi
  else
    warn GST-6 "QEMU guest agent is not running in VM $VMID (install the VirtIO guest tools)"
  fi
fi

section "Summary"
emit "  PASS $PASS | WARN $WARN | FAIL $FAIL"
if [ "$FAIL" -gt 0 ]; then
  emit "  result: FAIL"
else
  emit "  result: OK"
fi

if [ "$COMMANDS" -eq 1 ]; then
  print_commands
fi

if [ "$EXPLAIN" -eq 1 ]; then
  print_explanations
fi

if [ "$JSON" -eq 1 ]; then
  print_json
fi

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
