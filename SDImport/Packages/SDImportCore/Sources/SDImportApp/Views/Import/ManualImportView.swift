import SDImportCore
import SwiftUI

struct ManualImportView: View {
    @EnvironmentObject private var model: AppModel
    @AccessibilityFocusState private var phaseHeadingIsFocused: Bool

    var body: some View {
        Group {
            switch model.importUIPhase {
            case .source:
                sourcePage
            case .scanning:
                scanningPage
            case .review:
                ImportPreviewView()
            case .preparing:
                preparingPage
            case .copying:
                copyingPage
            case .completed:
                completionPage
            case .failed, .cancelled:
                recoveryPage
            }
        }
        .navigationTitle("Import")
        .onAppear {
            model.refreshAvailableSourceVolumes()
            model.validatePaths()
        }
        .onChange(of: model.cardPath) {
            model.sourcePathDidChange()
        }
        .onChange(of: model.photosPath) {
            model.destinationPathDidChange()
        }
        .onChange(of: model.videosPath) {
            model.destinationPathDidChange()
        }
        .onChange(of: model.importUIPhase) {
            phaseHeadingIsFocused = true
        }
    }

    private var sourcePage: some View {
        AppPage(status: visibleStatus) {
            VStack(alignment: .leading, spacing: 18) {
                phaseHeading("Choose a source", detail: "Select a card or folder, then scan it before anything is copied.")
                sourceSection
            }
        }
    }

    private var scanningPage: some View {
        AppPage {
            VStack(alignment: .leading, spacing: 18) {
                phaseHeading("Scanning source", detail: "Reading media and checking previous imports.")
                ImportSourceSummaryView(allowsChange: false)
                AppSection("Scanning", systemImage: "magnifyingglass") {
                    ProgressView()
                        .controlSize(.small)
                    Button(role: .cancel) {
                        model.cancelImport()
                    } label: {
                        Label("Cancel Scan", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("import.cancel.scan")
                }
            }
        }
    }

    private var preparingPage: some View {
        AppPage {
            VStack(alignment: .leading, spacing: 18) {
                phaseHeading("Preparing import", detail: model.statusMessage)
                AppSection("Preparing", systemImage: "gearshape.2") {
                    ProgressView()
                        .controlSize(.small)
                    Button(role: .cancel) {
                        model.cancelImport()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("import.cancel.preparation")
                }
            }
        }
    }

    @ViewBuilder
    private var copyingPage: some View {
        if let progress = model.importProgress {
            AppPage {
                VStack(alignment: .leading, spacing: 18) {
                    phaseHeading("Copying files", detail: "Keep the source connected until copying finishes.")
                    ImportProgressPanel(progress: progress) {
                        model.cancelImport()
                    }
                }
            }
        } else {
            preparingPage
        }
    }

    @ViewBuilder
    private var completionPage: some View {
        if let result = model.currentResult {
            AppPage {
                VStack(alignment: .leading, spacing: 18) {
                    phaseHeading(
                        result.failedFiles == 0 ? "Import complete" : "Completed with errors",
                        detail: result.failedFiles == 0
                            ? "Your copied files are ready."
                            : "Review the failed files before removing the source."
                    )
                    ImportResultView(result: result)
                }
            }
        } else {
            recoveryPage
        }
    }

    private var recoveryPage: some View {
        AppPage {
            VStack(alignment: .leading, spacing: 18) {
                phaseHeading(
                    model.importUIPhase == .cancelled ? "Operation cancelled" : "Import needs attention",
                    detail: model.importFailure?.message ?? model.statusMessage
                )

                AppSection(
                    model.importUIPhase == .cancelled ? "Cancelled" : "Couldn’t Continue",
                    systemImage: model.importUIPhase == .cancelled ? "xmark.circle" : "exclamationmark.triangle"
                ) {
                    Text(model.importFailure?.message ?? model.statusMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if model.importUIPhase == .failed {
                            Button("Retry") {
                                model.retryFailedImportOperation()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(recoveryButtonTitle) {
                            if model.currentResult != nil {
                                model.recoverImportReceipt()
                            } else {
                                model.recoverImportWorkspace()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func phaseHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityFocused($phaseHeadingIsFocused)
                .accessibilityIdentifier("import.phase.\(model.importUIPhase.rawValue).heading")
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recoveryButtonTitle: String {
        if model.currentResult != nil {
            return "Back to Receipt"
        }
        return model.currentSummary == nil ? "Back to Source" : "Back to Review"
    }

    private var visibleStatus: String? {
        guard model.statusMessage != "Ready", !model.statusMessage.isEmpty else {
            return nil
        }
        return model.statusMessage
    }

    private var sourceSection: some View {
        AppSection("Source", systemImage: "externaldrive") {
            SourceField()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    sourceActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    sourceActions
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.isWorking || model.isEjectingSource)
    }

    private var sourceActions: some View {
        Group {
            Button {
                model.scan()
            } label: {
                Label(scanButtonTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canScan)
            .accessibilityIdentifier("import.scan")

            if model.shouldOfferSelectedSourceEjection {
                Button {
                    model.ejectSelectedSource()
                } label: {
                    Label(model.selectedSourceEjectionButtonTitle, systemImage: "eject.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canEjectSelectedSource)
                .accessibilityHint("Safely unmounts all storage volumes on the selected source device")
            }

        }
    }

    private var scanButtonTitle: String {
        model.currentSummary == nil ? "Scan Card" : "Scan Again"
    }
}

struct ImportSourceSummaryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isConfirmingSourceChange = false

    var allowsChange = true
    var allowsRescan = false

    var body: some View {
        AppSection("Source", systemImage: "externaldrive") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    sourceIdentity
                    Spacer(minLength: 12)
                    actions
                }

                VStack(alignment: .leading, spacing: 10) {
                    sourceIdentity
                    actions
                }
            }
        }
        .alert("Change source?", isPresented: $isConfirmingSourceChange) {
            Button("Change Source") {
                model.sourcePathDidChange()
            }
            Button("Keep Review", role: .cancel) {}
        } message: {
            Text("The current scan and review will be discarded. No copied files are deleted.")
        }
    }

    private var sourceIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sourceTitle)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(sourceDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.cardPath)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source, \(sourceTitle), \(sourceDetail)")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if allowsRescan {
                Button {
                    model.scan()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canScan)
            }

            if model.shouldOfferSelectedSourceEjection {
                Button {
                    model.ejectSelectedSource()
                } label: {
                    Label("Eject", systemImage: "eject")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canEjectSelectedSource)
            }

            if allowsChange {
                Button("Change…") {
                    isConfirmingSourceChange = true
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking || model.isEjectingSource)
            }
        }
    }

    private var sourceTitle: String {
        model.selectedSourceVolume?.name
            ?? URL(fileURLWithPath: model.cardPath, isDirectory: true).lastPathComponent.nilIfBlank
            ?? "Source Folder"
    }

    private var sourceDetail: String {
        if let volume = model.selectedSourceVolume {
            return volume.detailText
        }
        if let summary = model.currentSummary {
            return "\(summary.scannedFiles) scanned files · \(model.cardPath)"
        }
        return model.cardPath
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

struct ImportDestinationFields: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Text("Shoot")
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                ShootNameField(name: $model.location, width: 260)
            }

            switch model.importMediaSelection {
            case .photosAndVideos:
                switch model.destinationLayout {
                case .singleLibrary:
                    GridRow {
                        Text("Library")
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        FolderField(
                            title: "Library",
                            path: $model.photosPath,
                            validation: model.photosValidation,
                            recentChoices: model.recentPhotosPathSuggestions,
                            selectRecentPath: model.selectPhotosPath,
                            action: model.choosePhotosFolder
                        )
                    }
                case .separateMediaFolders:
                    GridRow {
                        Text("Photos")
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        FolderField(
                            title: "Photos",
                            path: $model.photosPath,
                            validation: model.photosValidation,
                            recentChoices: model.recentPhotosPathSuggestions,
                            selectRecentPath: model.selectPhotosPath,
                            action: model.choosePhotosFolder
                        )
                    }

                    GridRow {
                        Text("Videos")
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        FolderField(
                            title: "Videos",
                            path: $model.videosPath,
                            validation: model.videosValidation,
                            recentChoices: model.recentVideosPathSuggestions,
                            selectRecentPath: model.selectVideosPath,
                            action: model.chooseVideosFolder
                        )
                    }
                case .footageBackup:
                    EmptyView()
                }
            case .photosOnly:
                GridRow {
                    Text("Photos")
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    FolderField(
                        title: "Photos",
                        path: $model.photosPath,
                        validation: model.photosValidation,
                        recentChoices: model.recentPhotosPathSuggestions,
                        selectRecentPath: model.selectPhotosPath,
                        action: model.choosePhotosFolder
                    )
                }
            case .videosOnly:
                GridRow {
                    Text("Videos")
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    FolderField(
                        title: "Videos",
                        path: $model.videosPath,
                        validation: model.videosValidation,
                        recentChoices: model.recentVideosPathSuggestions,
                        selectRecentPath: model.selectVideosPath,
                        action: model.chooseVideosFolder
                    )
                }
            }
        }
        .gridColumnAlignment(.leading)
    }
}

private struct SourceField: View {
    @EnvironmentObject private var model: AppModel
    @State private var isManagingRecentSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    sourcePathField
                    sourceControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    sourcePathField
                    sourceControls
                }
            }

            if let selectedVolume = model.selectedSourceVolume {
                Label(selectedVolume.detailText, systemImage: "externaldrive")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ValidationStatusView(result: model.sourceValidation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourcePathField: some View {
        TextField("Card or source path", text: $model.cardPath)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .frame(minWidth: 180, maxWidth: 420)
    }

    private var sourceControls: some View {
        HStack(spacing: 8) {
            sourceMenu

            Button {
                model.refreshAvailableSourceVolumes()
                model.validatePaths()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh mounted cards")
            .accessibilityLabel("Refresh mounted cards")

            Button {
                model.chooseCardFolder()
            } label: {
                Image(systemName: "folder")
            }
            .help("Choose source folder")
            .accessibilityLabel("Choose source folder")
        }
    }

    private var sourceMenu: some View {
        Menu {
            if model.availableSourceVolumes.isEmpty && model.recentSourcePathSuggestions.isEmpty {
                Text("No cards or recent sources")
            }

            if !model.availableSourceVolumes.isEmpty {
                Section("Mounted Cards") {
                    ForEach(model.availableSourceDeviceGroups) { group in
                        ForEach(group.volumes) { volume in
                            Button {
                                model.selectSourceVolume(volume)
                            } label: {
                                Text(
                                    volume.menuTitle(
                                        deviceName: group.isMultiVolume ? group.displayName : nil
                                    )
                                )
                            }
                        }
                    }
                }
            }

            if !model.recentSourcePathSuggestions.isEmpty {
                Section("Recent Sources") {
                    ForEach(model.recentSourcePathSuggestions) { suggestion in
                        Button {
                            model.selectSourcePath(suggestion.path)
                        } label: {
                            Label(
                                suggestion.menuTitle,
                                systemImage: suggestion.isAvailable ? "externaldrive" : "exclamationmark.triangle"
                            )
                        }
                        .disabled(!suggestion.isAvailable)
                        .help(suggestion.path)
                    }
                }
            }

            Divider()

            Button {
                isManagingRecentSources = true
            } label: {
                Label("Manage Recent Sources...", systemImage: "slider.horizontal.3")
            }
            .disabled(model.recentSourcePathSuggestions.isEmpty)

            if model.hasForgottenRecentPaths {
                Button {
                    model.restoreForgottenRecentPaths()
                } label: {
                    Label("Show Forgotten Folders Again", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label(sourceMenuTitle, systemImage: "sdcard")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .leading)
        }
        .help("Select source")
        .accessibilityLabel("Select source")
        .sheet(isPresented: $isManagingRecentSources) {
            RecentPathManagementSheet(
                title: "Recent Sources",
                choices: model.recentSourcePathSuggestions,
                selectRecentPath: model.selectSourcePath,
                forgetRecentPath: model.forgetRecentPath
            )
        }
    }

    private var sourceMenuTitle: String {
        model.selectedSourceVolume?.name ?? "Sources"
    }
}

private extension MountedVolume {
    func menuTitle(deviceName: String?) -> String {
        let identity = if let deviceName {
            "\(name) · \(deviceName)"
        } else {
            name
        }

        if let capacityText {
            return "\(identity) · \(capacityText)"
        }
        return identity
    }

    var detailText: String {
        if let capacityText {
            return "\(name): \(capacityText) · \(mountURL.path)"
        }
        return "\(name): \(mountURL.path)"
    }

    private var capacityText: String? {
        guard let availableCapacityBytes else {
            return nil
        }

        let available = ByteCountFormatter.string(fromByteCount: availableCapacityBytes, countStyle: .file)
        if let usedCapacityBytes, let totalCapacityBytes {
            let used = ByteCountFormatter.string(fromByteCount: usedCapacityBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalCapacityBytes, countStyle: .file)
            return "\(available) free, \(used) used of \(total)"
        }

        return "\(available) free"
    }
}

private struct FolderField: View {
    @EnvironmentObject private var model: AppModel
    @State private var isManagingRecentFolders = false

    let title: String
    @Binding var path: String
    let validation: PathValidationResult
    let recentChoices: [RecentPathSuggestion]
    let selectRecentPath: (String) -> Void
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("\(title) folder path", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .frame(minWidth: 180, maxWidth: 420)

                Menu {
                    if recentChoices.isEmpty {
                        Text("No recent folders")
                    } else {
                        ForEach(recentChoices) { suggestion in
                            Button {
                                selectRecentPath(suggestion.path)
                            } label: {
                                Label(
                                    suggestion.menuTitle,
                                    systemImage: suggestion.isAvailable ? "folder" : "exclamationmark.triangle"
                                )
                            }
                            .disabled(!suggestion.isAvailable)
                            .help(suggestion.path)
                        }
                    }

                    Divider()

                    Button {
                        isManagingRecentFolders = true
                    } label: {
                        Label("Manage Recent Folders...", systemImage: "slider.horizontal.3")
                    }
                    .disabled(recentChoices.isEmpty)

                    if model.hasForgottenRecentPaths {
                        Button {
                            model.restoreForgottenRecentPaths()
                        } label: {
                            Label("Show Forgotten Folders Again", systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("Choose recent \(title.lowercased()) folder")
                .accessibilityLabel("Choose recent \(title.lowercased()) folder")
                .sheet(isPresented: $isManagingRecentFolders) {
                    RecentPathManagementSheet(
                        title: "Recent \(title) Folders",
                        choices: recentChoices,
                        selectRecentPath: selectRecentPath,
                        forgetRecentPath: model.forgetRecentPath
                    )
                }

                Button {
                    action()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Choose \(title.lowercased()) folder")
                .accessibilityLabel("Choose \(title.lowercased()) folder")
            }

            ValidationStatusView(result: validation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentPathManagementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let choices: [RecentPathSuggestion]
    let selectRecentPath: (String) -> Void
    let forgetRecentPath: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            if choices.isEmpty {
                ContentUnavailableView("No Recent Folders", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(choices) { suggestion in
                            RecentPathManagementRow(
                                suggestion: suggestion,
                                selectRecentPath: {
                                    selectRecentPath(suggestion.path)
                                    dismiss()
                                },
                                forgetRecentPath: {
                                    forgetRecentPath(suggestion.path)
                                }
                            )

                            if suggestion.id != choices.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180, idealHeight: 260, maxHeight: 320)
                .appCardSurface()
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 260)
    }
}

private struct RecentPathManagementRow: View {
    let suggestion: RecentPathSuggestion
    let selectRecentPath: () -> Void
    let forgetRecentPath: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: suggestion.isAvailable ? "folder" : "exclamationmark.triangle")
                .foregroundStyle(suggestion.isAvailable ? Color.secondary : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.displayName)
                    .lineLimit(1)

                Text(suggestion.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Button {
                selectRecentPath()
            } label: {
                Label("Use", systemImage: "checkmark")
            }
            .disabled(!suggestion.isAvailable)
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                forgetRecentPath()
            } label: {
                Label("Forget", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }

    private var detailText: String {
        let usage = suggestion.choice.useCount == 1 ? "used once" : "used \(suggestion.choice.useCount) times"
        return "\(suggestion.validation.message) · \(usage)"
    }
}

private struct ValidationStatusView: View {
    let result: PathValidationResult

    var body: some View {
        AppStatusLabel(
            title: result.message,
            systemImage: result.isUsable ? "checkmark.circle" : "exclamationmark.triangle",
            role: result.isUsable ? .neutral : .warning
        )
            .font(.callout)
            .lineLimit(1)
    }
}
