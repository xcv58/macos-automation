# SD Import 2.3

## Changes

- Recognizes cameras that mount internal storage and a memory card as separate
  volumes on the same physical USB device.
- Shows each mounted camera volume as a direct source choice, labeled with its
  physical device when macOS provides that identity.
- Adds a persistent source eject action so the device can be safely removed
  before copying, after scanning, or when there are no files to copy.
- Ejects every verified storage volume that belongs to the selected physical
  device and reports partial failures without force-ejecting busy volumes.
- Keeps automatic and receipt-based ejection disabled when an import
  destination is on the same physical device.

## Compatibility

Multi-volume grouping depends on the hardware identity reported by macOS.
Devices that do not expose a shared USB identity may continue to appear as
separate ejectable sources.
