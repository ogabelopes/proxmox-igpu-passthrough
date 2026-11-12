# Glossary

| Term | Meaning |
| ---- | ------- |
| **APU** | AMD's name for a CPU with integrated graphics (e.g. Ryzen 9 6900HX). |
| **iGPU** | The integrated GPU itself (e.g. Radeon 680M). |
| **IOMMU** | Hardware unit that isolates devices for assignment (AMD-Vi, Intel VT-d). |
| **IOMMU group** | The smallest set of devices that can be assigned to a VM together. |
| **VFIO** | Linux framework that hands a device to QEMU; `vfio-pci` is the driver. |
| **Passthrough** | Giving a physical device to a VM so the guest owns it directly. |
| **FLR** | Function-Level Reset. The 680M does not support it; that is the root of the reset bug. |
| **Reset bug** | The GPU failing to re-initialise after a warm reset (only a power cycle clears it). |
| **VBIOS** | The GPU's firmware/option ROM. |
| **GOP** | Graphics Output Protocol driver inside the ROM, used by UEFI. |
| **OVMF** | Open Virtual Machine Firmware: UEFI for QEMU. |
| **UMA frame buffer** | System RAM reserved by firmware as GPU memory on an APU. |
| **BAR** | PCI Base Address Register: one of the GPU's memory windows. |
| **ACS** | Access Control Services: controls how PCIe devices share IOMMU groups. |
| **Error 43** | Windows' generic "this device has reported problems" code; in practice the driver could not start the GPU. |
| **Cold start** | Powering the VM off and on (not a guest-initiated reboot). |
| **Warm reset** | A reset without power loss, e.g. a Windows restart. |
