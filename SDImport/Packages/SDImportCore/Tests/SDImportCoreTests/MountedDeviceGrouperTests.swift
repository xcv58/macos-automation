import Foundation
import Testing

@testable import SDImportCore

@Suite("Mounted device grouping")
struct MountedDeviceGrouperTests {
    private let grouper = MountedDeviceGrouper()

    @Test("groups separate whole disks under the same physical device")
    func groupsSeparateWholeDisks() {
        let card = makeVolume(
            id: "card",
            name: "Untitled",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: "usb-pocket"
        )
        let internalStorage = makeVolume(
            id: "internal",
            name: "Pocket4",
            wholeDiskIdentifier: "disk5",
            deviceGroupIdentifier: "usb-pocket"
        )

        let groups = grouper.groups(from: [card, internalStorage])

        #expect(groups.count == 1)
        #expect(groups[0].displayName == "DJI OsmoPocket4")
        #expect(groups[0].volumes.map(\.name) == ["Pocket4", "Untitled"])
        #expect(grouper.ejectionVolumes(for: card, among: [card, internalStorage]).map(\.id) == [
            "internal",
            "card"
        ])
    }

    @Test("deduplicates multiple volumes on the same whole disk")
    func deduplicatesPartitionsForEjection() {
        let source = makeVolume(
            id: "source",
            name: "Photos",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: "usb-camera"
        )
        let sideVolume = makeVolume(
            id: "side",
            name: "Metadata",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: "usb-camera"
        )

        let ejectionVolumes = grouper.ejectionVolumes(for: source, among: [source, sideVolume])

        #expect(ejectionVolumes.map(\.id) == ["source"])
    }

    @Test("does not group matching product names from different devices")
    func keepsDifferentDevicesSeparate() {
        let first = makeVolume(
            id: "first",
            name: "CARD A",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: "usb-device-a"
        )
        let second = makeVolume(
            id: "second",
            name: "CARD B",
            wholeDiskIdentifier: "disk5",
            deviceGroupIdentifier: "usb-device-b"
        )

        let groups = grouper.groups(from: [first, second])

        #expect(groups.count == 2)
    }

    @Test("falls back to whole disk identity when hardware identity is unavailable")
    func fallsBackToWholeDisk() {
        let first = makeVolume(
            id: "first",
            name: "CARD",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: nil
        )
        let second = makeVolume(
            id: "second",
            name: "SIDECAR",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: nil
        )

        let groups = grouper.groups(from: [first, second])

        #expect(groups.count == 1)
    }

    @Test("does not add unsafe siblings to an ejection group")
    func excludesUnsafeSiblings() {
        let source = makeVolume(
            id: "source",
            name: "CARD",
            wholeDiskIdentifier: "disk4",
            deviceGroupIdentifier: "usb-device"
        )
        let diskImage = makeVolume(
            id: "image",
            name: "Installer",
            wholeDiskIdentifier: "disk5",
            deviceGroupIdentifier: "usb-device",
            isDiskImage: true
        )

        let group = grouper.group(containing: source, among: [source, diskImage])

        #expect(group.volumes.map(\.id) == ["source"])
    }

    private func makeVolume(
        id: String,
        name: String,
        wholeDiskIdentifier: String?,
        deviceGroupIdentifier: String?,
        isDiskImage: Bool = false
    ) -> MountedVolume {
        MountedVolume(
            id: id,
            name: name,
            mountURL: URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true),
            volumeUUID: id,
            isRemovable: true,
            isDiskImage: isDiskImage,
            wholeDiskIdentifier: wholeDiskIdentifier,
            deviceGroupIdentifier: deviceGroupIdentifier,
            deviceVendorName: "DJI",
            deviceProductName: "OsmoPocket4"
        )
    }
}
