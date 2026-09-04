import SDImportCommerce
import SwiftUI

struct PurchaseView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 38))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 6) {
                Text("Unlock Unlimited Imports")
                    .font(.title2.bold())
                Text("Keep previewing every card for free. A one-time purchase unlocks unlimited completed imports.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(purchaseManager.allowanceSummary, systemImage: "checkmark.circle")

            if purchaseManager.isFamilyShareable {
                Label("Shareable with Family Sharing", systemImage: "person.3")
            }

            if let status = purchaseManager.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Not Now") {
                    dismiss()
                }

                Spacer()

                Button("Restore Purchases") {
                    Task {
                        await purchaseManager.restorePurchases()
                        if purchaseManager.hasLifetimeUnlock {
                            dismiss()
                        }
                    }
                }
                .disabled(purchaseManager.isPerformingStoreOperation)

                Button(purchaseButtonTitle) {
                    Task {
                        if purchaseManager.productDisplayPrice == nil {
                            await purchaseManager.refreshStoreState()
                        } else {
                            await purchaseManager.purchase()
                        }
                        if purchaseManager.hasLifetimeUnlock {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(purchaseManager.isPerformingStoreOperation)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var purchaseButtonTitle: String {
        if let price = purchaseManager.productDisplayPrice {
            return "Buy for \(price)"
        }
        return purchaseManager.isPerformingStoreOperation ? "Loading…" : "Try Again"
    }
}
