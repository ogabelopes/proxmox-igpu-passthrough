# BIOS checklist

Settings that matter before you start. Names vary by vendor; the AMI/Beelink style is in
parentheses.

| Setting | Value | Why |
| ------- | ----- | --- |
| IOMMU / AMD-Vi (`IOMMU`) | Enabled | Without it the kernel cannot isolate the GPU for assignment |
| SVM (`SVM Mode`) | Enabled | Required by KVM |
| Above 4G Decoding | Enabled | The GPU BARs live above 4 GB |
| Resizable BAR | Try both | Large BARs can help, but on some APUs the resize path fails |
| UMA Frame Buffer Size (`iGPU Memory`) | 512 MB or 1 GB | A 4 GB carve-out can break the host `amdgpu` aperture and wastes RAM |
| Primary display (`Primary Video Device`) | iGPU / Auto | The Radeon has to drive the HDMI output |
| CSM | Disabled | UEFI/OVMF only |
| Secure Boot (guest) | Try without first | Unsigned option ROMs and drivers can fail under Secure Boot |

## The UMA frame buffer is not just "VRAM"

On Rembrandt APUs the firmware reserves a block of system RAM as GPU memory. At 4 GB this
machine made the **host** `amdgpu` fail with:

```text
memtype_reserve failed: [mem ...], req write-combining
amdgpu_bo_init: Unable to set WC memtype for the aperture base
```

That blocks the host-side rebind workaround, not just the guest. 512 MB or 1 GB is a good
starting point; it also changes the VRAM Windows reports.

## After changing a setting

1. Reboot the host.
2. Run `sudo ./scripts/check-passthrough.sh --vmid <id> --explain`.
3. If the GPU cannot be reset between runs, read [reset-bug](reset-bug.md).
