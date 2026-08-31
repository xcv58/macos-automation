import Foundation
import Testing

@testable import SDImportCore

#if DEBUG
@Suite("Background prompt runtime QA boundary")
struct BackgroundPromptRuntimeQATests {
    @Test("parses only explicit debug QA arguments")
    func parsesExplicitArguments() {
        #expect(
            BackgroundPromptRuntimeQA.preparesApplication(
                arguments: ["agent", BackgroundPromptRuntimeQA.prepareApplicationArgument],
                distribution: .macAppStore
            )
        )
        #expect(
            BackgroundPromptRuntimeQA.unregistersHelper(
                arguments: ["agent", BackgroundPromptRuntimeQA.unregisterHelperArgument],
                distribution: .macAppStore
            )
        )
        #expect(
            BackgroundPromptRuntimeQA.consumesInjectedHandoff(
                arguments: ["app", BackgroundPromptRuntimeQA.consumeHandoffArgument],
                distribution: .macAppStore
            )
        )
        #expect(
            !BackgroundPromptRuntimeQA.preparesApplication(
                arguments: ["agent"],
                distribution: .macAppStore
            )
        )
        #expect(
            !BackgroundPromptRuntimeQA.consumesInjectedHandoff(
                arguments: ["app", BackgroundPromptRuntimeQA.consumeHandoffArgument],
                distribution: .direct
            )
        )
        #expect(
            !BackgroundPromptRuntimeQA.unregistersHelper(
                arguments: ["agent"],
                distribution: .macAppStore
            )
        )
        #expect(
            !BackgroundPromptRuntimeQA.preparesApplication(
                arguments: ["agent", BackgroundPromptRuntimeQA.prepareApplicationArgument],
                distribution: .direct
            )
        )
    }

    @Test("accepts only mounted-volume paths for injected post-detection events")
    func parsesMountedVolumePath() {
        let mountURL = BackgroundPromptRuntimeQA.injectedMountURL(
            arguments: [
                "agent",
                BackgroundPromptRuntimeQA.injectedMountArgument,
                "/Volumes/SDIMPORT_QA_CARD",
            ],
            distribution: .macAppStore
        )
        #expect(mountURL?.path == "/Volumes/SDIMPORT_QA_CARD")
        #expect(
            BackgroundPromptRuntimeQA.injectedMountURL(
                arguments: [
                    "agent",
                    BackgroundPromptRuntimeQA.injectedMountArgument,
                    "/private/tmp/not-a-volume",
                ],
                distribution: .macAppStore
            ) == nil
        )
        #expect(
            BackgroundPromptRuntimeQA.injectedMountURL(
                arguments: ["agent", BackgroundPromptRuntimeQA.injectedMountArgument],
                distribution: .macAppStore
            ) == nil
        )
        #expect(
            BackgroundPromptRuntimeQA.injectedMountURL(
                arguments: [
                    "agent",
                    BackgroundPromptRuntimeQA.injectedMountArgument,
                    "/Volumes/SDIMPORT_QA_CARD",
                ],
                distribution: .direct
            ) == nil
        )
    }

    @Test("injected event starts after detection without capacity or media data")
    func createsPostDetectionEvent() throws {
        let mountURL = try #require(
            BackgroundPromptRuntimeQA.injectedMountURL(
                arguments: [
                    "agent",
                    BackgroundPromptRuntimeQA.injectedMountArgument,
                    "/Volumes/SDIMPORT_QA_CARD",
                ],
                distribution: .macAppStore
            )
        )
        let volume = BackgroundPromptRuntimeQA.injectedPostDetectionVolume(at: mountURL)

        #expect(volume.mountURL == mountURL)
        #expect(volume.name == "SDIMPORT_QA_CARD")
        #expect(volume.isRemovable)
        #expect(!volume.isDiskImage)
        #expect(volume.totalCapacityBytes == nil)
        #expect(volume.availableCapacityBytes == nil)
    }
}
#endif
