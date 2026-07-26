import SwiftUI

struct SourceEjectionControl: View {
    let sourceName: String
    let volumeCount: Int
    let isEjected: Bool
    let isEjecting: Bool
    let canEject: Bool
    let eject: () -> Void

    var body: some View {
        if isEjected {
            AppStatusLabel(
                title: "\(sourceName) Ejected — Safe to Remove",
                systemImage: "checkmark.circle.fill",
                role: .success
            )
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("\(sourceName) ejected. Safe to remove.")
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ejectButton
                    guidance
                }

                VStack(alignment: .leading, spacing: 6) {
                    ejectButton
                    guidance
                }
            }
        }
    }

    private var ejectButton: some View {
        Button(action: eject) {
            Label(
                isEjecting ? "Ejecting \(sourceName)…" : ejectButtonTitle,
                systemImage: "eject.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canEject)
        .accessibilityHint(
            volumeCount > 1
                ? "Safely unmounts all source volumes"
                : "Safely unmounts the source volume"
        )
    }

    private var guidance: some View {
        Text(
            volumeCount > 1
                ? "Unmounts all \(volumeCount) storage volumes before disconnecting the device."
                : "Eject the card before removing it."
        )
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var ejectButtonTitle: String {
        if volumeCount > 1 {
            return "Eject \(sourceName) — \(volumeCount) Volumes"
        }
        return "Eject “\(sourceName)”"
    }
}
