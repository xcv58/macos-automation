import AppKit
import SDImportCore
import SwiftUI

struct ImportPreviewView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("SDImport.importPreviewMode") private var previewMode = ImportPreviewMode.grid
    @State private var fileFilter: ImportPreviewFileFilter = .copy
    @State private var selectedRowID: Int64?
    @State private var showsDateCustomization = false
    @State private var showsZeroCopyFiles = false
    @StateObject private var thumbnailProvider = ImportThumbnailProvider()
    @StateObject private var quickLook = ImportQuickLookController()
    @AccessibilityFocusState private var reviewHeadingIsFocused: Bool

    private var displayedRows: [ImportPreviewRow] {
        sortedRows(model.previewRows.filter(fileFilter.includes))
    }

    private var selectedRow: ImportPreviewRow? {
        model.previewRows.first { $0.id == selectedRowID }
    }

    var body: some View {
        AppPage(maxContentWidth: .infinity) {
            VStack(alignment: .leading, spacing: 14) {
                reviewHeading
                ImportSourceSummaryView(
                    allowsChange: true,
                    allowsRescan: true,
                    compact: true
                )

                if model.previewTotals.copyFiles == 0 {
                    zeroCopyCard
                    if showsZeroCopyFiles {
                        fileBrowser
                    }
                } else {
                    importPlanCard
                    fileBrowser
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ImportReviewFooter()
                .environmentObject(model)
        }
        .inspector(isPresented: inspectorBinding) {
            if let selectedRow {
                ImportFileInspector(row: selectedRow) {
                    presentQuickLook(for: selectedRow)
                }
                .frame(minWidth: 260, idealWidth: 300)
            }
        }
        .onAppear {
            reviewHeadingIsFocused = true
        }
        .onChange(of: model.cardPath) {
            thumbnailProvider.cancelAll()
            quickLook.dismiss()
        }
        .onChange(of: model.importUIPhase) {
            if model.importUIPhase != .review {
                thumbnailProvider.cancelAll()
                quickLook.dismiss()
            }
        }
    }

    private var reviewHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Review import")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityFocused($reviewHeadingIsFocused)
                .accessibilityIdentifier("import.phase.review.heading")
            Text("Confirm what will be copied and where it will go.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var importPlanCard: some View {
        AppSection("Import Plan", systemImage: "list.bullet.rectangle") {
            reviewSummary

            if let mediaContent = model.mediaContentProfile {
                Label(mediaContentSummary(mediaContent), systemImage: "externaldrive.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            importOptionControls

            if hasSupportedMedia {
                ImportDestinationFields()
                defaultsAction
                sessionControls
            }

            portableReceiptOverride
            destinationTree

            if let warning = selectedMediaAvailabilityMessage {
                AppStatusLabel(
                    title: warning,
                    systemImage: "info.circle",
                    role: .warning
                )
                .font(.caption)
            }
        }
    }

    private var reviewSummary: some View {
        let summary = model.currentSummary
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                summaryPills(summary: summary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                summaryPills(summary: summary)
            }
        }
    }

    @ViewBuilder
    private func summaryPills(summary: ScanSummary?) -> some View {
        InfoPill(
            title: model.previewTotals.copyFiles == 1
                ? "1 file ready"
                : "\(model.previewTotals.copyFiles) files ready",
            systemImage: "arrow.down.circle",
            role: .success
        )
        InfoPill(
            title: ByteCountFormatter.string(fromByteCount: model.previewTotals.copyBytes, countStyle: .file),
            systemImage: "externaldrive"
        )
        if let summary, summary.knownFiles > 0 {
            InfoPill(title: "\(summary.knownFiles) known", systemImage: "checkmark.seal")
        }
        if model.previewAttentionCount > 0 {
            InfoPill(
                title: "\(model.previewAttentionCount) attention",
                systemImage: "exclamationmark.triangle",
                role: .warning
            )
        }
        if model.previewDestinationIssueCount > 0 {
            InfoPill(
                title: model.previewDestinationIssueCount == 1
                    ? "1 destination issue"
                    : "\(model.previewDestinationIssueCount) destination issues",
                systemImage: "externaldrive.badge.exclamationmark",
                role: .warning
            )
        }
    }

    private var importOptionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            optionRow("Copy") {
                Picker("Copy", selection: mediaSelectionBinding) {
                    ForEach(ImportMediaSelection.allCases) { selection in
                        Text(mediaSelectionTitle(selection))
                            .tag(selection)
                            .disabled(!isMediaSelectionAvailable(selection))
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if showsMixedDestinationLayout {
                optionRow("Save to") {
                    Picker("Save to", selection: destinationLayoutBinding) {
                        ForEach([ImportDestinationLayout.singleLibrary, .separateMediaFolders]) { layout in
                            Text(layout.displayTitle).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            optionRow("Organize") {
                Picker("Organize", selection: folderGroupingBinding) {
                    ForEach(ImportFolderGrouping.allCases) { grouping in
                        Text(grouping.displayTitle).tag(grouping)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private func optionRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .leading)
                content()
                    .frame(maxWidth: 440)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content()
                    .frame(maxWidth: 440)
            }
        }
    }

    @ViewBuilder
    private var defaultsAction: some View {
        if !model.importDraftUsesDefaults {
            HStack(spacing: 8) {
                AppStatusLabel(
                    title: "These choices apply to this import only",
                    systemImage: "info.circle",
                    role: .info
                )
                .font(.caption)

                Button("Use as Defaults") {
                    model.saveImportDraftAsDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        let unsupportedCount = model.previewSessions.reduce(0) { $0 + $1.unsupportedCount }

        if model.importMediaSelection == .videosOnly, unsupportedCount > 0 {
            Toggle(
                "Include camera support files (\(unsupportedCount))",
                isOn: allSessionsBinding(\.includeSidecars)
            )
            .help("Includes metadata, proxy, audio, thumbnail, and other camera support files in footage backups.")
        }

        if model.folderGrouping == .byDay, model.previewSessions.count > 1 {
            DisclosureGroup("Customize Dates", isExpanded: $showsDateCustomization) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($model.previewSessions) { $session in
                        sessionEditor(session: $session)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func sessionEditor(session: Binding<ImportPreviewSession>) -> some View {
        let value = session.wrappedValue
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(value.date)
                    .font(.system(.callout, design: .monospaced))
                    .frame(width: 96, alignment: .leading)
                TextField("Folder label", text: session.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                if value.photoCount > 0 {
                    mediaSessionControl(
                        title: "Photos \(value.photoCount)",
                        isGloballyIncluded: model.importMediaSelection.includes(.photo),
                        isIncluded: session.includePhotos
                    )
                }
                if value.videoCount > 0 {
                    mediaSessionControl(
                        title: "Videos \(value.videoCount)",
                        isGloballyIncluded: model.importMediaSelection.includes(.video),
                        isIncluded: session.includeVideos
                    )
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(value.date)
                    .font(.system(.callout, design: .monospaced))
                TextField("Folder label", text: session.label)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    if value.photoCount > 0 {
                        mediaSessionControl(
                            title: "Photos \(value.photoCount)",
                            isGloballyIncluded: model.importMediaSelection.includes(.photo),
                            isIncluded: session.includePhotos
                        )
                    }
                    if value.videoCount > 0 {
                        mediaSessionControl(
                            title: "Videos \(value.videoCount)",
                            isGloballyIncluded: model.importMediaSelection.includes(.video),
                            isIncluded: session.includeVideos
                        )
                    }
                }
            }
        }
        .padding(10)
        .appCardSurface(cornerRadius: 6)
    }

    @ViewBuilder
    private func mediaSessionControl(
        title: String,
        isGloballyIncluded: Bool,
        isIncluded: Binding<Bool>
    ) -> some View {
        if isGloballyIncluded {
            Toggle(title, isOn: isIncluded)
        } else {
            Text("\(title) excluded")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(title), excluded by Copy selection")
        }
    }

    @ViewBuilder
    private var portableReceiptOverride: some View {
        let count = model.previewRows.filter(\.isPortableKnown).count
        if count > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    portableReceiptLabel(count: count)
                    Button("Import Anyway") {
                        model.importPortableKnownFilesAnyway()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    portableReceiptLabel(count: count)
                    Button("Import Anyway") {
                        model.importPortableKnownFilesAnyway()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func portableReceiptLabel(count: Int) -> some View {
        AppStatusLabel(
            title: count == 1
                ? "1 file was imported on another Mac"
                : "\(count) files were imported on another Mac",
            systemImage: "externaldrive.badge.checkmark",
            role: .neutral
        )
        .font(.caption)
    }

    @ViewBuilder
    private var destinationTree: some View {
        if !model.previewDestinations.isEmpty || !model.previewSpaceRequirements.isEmpty {
            Divider()
            Text("Destinations")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(model.previewDestinations) { destination in
                DestinationTreeRow(
                    destination: destination,
                    rootTitle: destinationRootTitle(for: destination)
                )
            }

            ForEach(model.previewSpaceRequirements) { requirement in
                AppStatusLabel(
                    title: spaceText(for: requirement),
                    systemImage: requirement.isSatisfied ? "checkmark.circle" : "exclamationmark.triangle",
                    role: requirement.isSatisfied ? .neutral : .warning
                )
                .font(.caption)
            }
        }
    }

    private var zeroCopyCard: some View {
        AppSection("Nothing New", systemImage: "checkmark.seal") {
            Text(zeroCopyTitle)
                .font(.headline)
            Text(zeroCopyDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasSupportedMedia {
                Divider()
                importOptionControls
                ImportDestinationFields()
                defaultsAction
                sessionControls
            }

            portableReceiptOverride

            HStack(spacing: 8) {
                if canRecoverPhotos {
                    Button("Import Photos") {
                        fileFilter = .copy
                        model.applyWorkflowProfile(.photoImport)
                    }
                    .buttonStyle(.bordered)
                }
                if canRecoverVideos {
                    Button("Import Videos") {
                        fileFilter = .copy
                        model.applyWorkflowProfile(.footageBackup)
                    }
                    .buttonStyle(.bordered)
                }

                if !model.previewRows.isEmpty {
                    Button(showsZeroCopyFiles ? "Hide File Details" : zeroCopyReviewButtonTitle) {
                        if showsZeroCopyFiles {
                            showsZeroCopyFiles = false
                        } else {
                            fileFilter = .skipped
                            showsZeroCopyFiles = true
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var zeroCopyReviewButtonTitle: String {
        let skippedCount = model.previewRows.filter { !$0.willCopy }.count
        return skippedCount == 1 ? "Review 1 Skipped File" : "Review \(skippedCount) Skipped Files"
    }

    private var fileBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            fileBrowserToolbar

            Group {
                if displayedRows.isEmpty {
                    ContentUnavailableView(
                        "No Matching Files",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if previewMode == .list {
                    fileTable
                } else {
                    fileGrid
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Import file preview")
        }
        .padding(14)
        .appCardSurface()
    }

    private var fileBrowserToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                fileBrowserHeading
                Spacer(minLength: 8)
                filterPicker
                modePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                fileBrowserHeading
                HStack(spacing: 8) {
                    filterMenu
                    modePicker
                }
            }
        }
    }

    private var fileBrowserHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Files")
                .font(.headline)
            Text("\(displayedRows.count) of \(model.previewRows.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var filterPicker: some View {
        Picker("File Filter", selection: $fileFilter) {
            ForEach(ImportPreviewFileFilter.allCases) { filter in
                Text(filterTitle(filter)).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 430)
        .accessibilityLabel("File filter")
        .accessibilityIdentifier("import.review.file-filter")
    }

    private var filterMenu: some View {
        Picker("File Filter", selection: $fileFilter) {
            ForEach(ImportPreviewFileFilter.allCases) { filter in
                Text(filterTitle(filter)).tag(filter)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180)
    }

    private var modePicker: some View {
        Picker("Preview Mode", selection: $previewMode) {
            Label("List", systemImage: "list.bullet").tag(ImportPreviewMode.list)
            Label("Grid", systemImage: "square.grid.2x2").tag(ImportPreviewMode.grid)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 120)
        .accessibilityLabel("Preview mode")
        .accessibilityIdentifier("import.review.preview-mode")
    }

    private var fileTable: some View {
        LazyVStack(spacing: 0) {
            fileListHeader

            ForEach(displayedRows) { row in
                Button {
                    selectedRowID = row.id
                } label: {
                    ImportPreviewListRow(
                        row: row,
                        destinationText: destinationText(for: row),
                        isSelected: selectedRowID == row.id
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    selectedRowID = row.id
                    presentQuickLook(for: row)
                })
                .contextMenu {
                    Button("Quick Look") {
                        selectedRowID = row.id
                        presentQuickLook(for: row)
                    }
                }
                .accessibilityHint("Press Space for Quick Look")
            }
        }
        .onKeyPress(.space) {
            presentSelectedQuickLook()
            return .handled
        }
        .accessibilityIdentifier("import.review.file-table")
    }

    private var fileListHeader: some View {
        HStack(spacing: 12) {
            Text("Status")
                .frame(width: 112, alignment: .leading)
            Text("File")
                .frame(minWidth: 150, maxWidth: 240, alignment: .leading)
            Text("Kind")
                .frame(width: 72, alignment: .leading)
            Text("Size")
                .frame(width: 80, alignment: .trailing)
            Text("Destination")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06))
        .accessibilityHidden(true)
    }

    private var fileGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(visualItems(from: displayedRows)) { item in
                Button {
                    selectedRowID = item.primaryRow.id
                } label: {
                    ImportPreviewGridCell(
                        item: item,
                        isSelected: item.rows.contains { $0.id == selectedRowID },
                        thumbnailProvider: thumbnailProvider
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    selectedRowID = item.primaryRow.id
                    presentQuickLook(for: item.primaryRow)
                })
                .onKeyPress(.space) {
                    selectedRowID = item.primaryRow.id
                    presentQuickLook(for: item.primaryRow)
                    return .handled
                }
                .accessibilityHint("Press Space for Quick Look")
                .accessibilityIdentifier("import.review.grid-item.\(item.primaryRow.id)")
            }
        }
        .padding(.vertical, 4)
        .onKeyPress(.space) {
            presentSelectedQuickLook()
            return .handled
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding {
            selectedRow != nil
        } set: { isPresented in
            if !isPresented {
                selectedRowID = nil
            }
        }
    }

    private var mediaSelectionBinding: Binding<ImportMediaSelection> {
        Binding {
            model.importMediaSelection
        } set: { selection in
            model.useImportMediaSelection(selection)
        }
    }

    private var destinationLayoutBinding: Binding<ImportDestinationLayout> {
        Binding {
            model.destinationLayout
        } set: { layout in
            model.useDestinationLayout(layout)
        }
    }

    private var folderGroupingBinding: Binding<ImportFolderGrouping> {
        Binding {
            model.folderGrouping
        } set: { grouping in
            model.useFolderGrouping(grouping)
        }
    }

    private func allSessionsBinding(
        _ keyPath: WritableKeyPath<ImportPreviewSession, Bool>
    ) -> Binding<Bool> {
        Binding {
            model.previewSessions.contains { $0[keyPath: keyPath] }
        } set: { isIncluded in
            model.setPreviewSessionInclusion(keyPath, to: isIncluded)
        }
    }

    private var hasSupportedMedia: Bool {
        model.mediaContentProfile?.supportedCount ?? 1 > 0
    }

    private var showsMixedDestinationLayout: Bool {
        model.importMediaSelection == .photosAndVideos
            && (model.mediaContentProfile?.photoCount ?? 1) > 0
            && (model.mediaContentProfile?.videoCount ?? 1) > 0
    }

    private var selectedMediaAvailabilityMessage: String? {
        guard !isMediaSelectionAvailable(model.importMediaSelection) else {
            return nil
        }
        switch model.importMediaSelection {
        case .photosAndVideos:
            return "This source does not contain both photos and videos."
        case .photosOnly:
            return "No photos were found on this source."
        case .videosOnly:
            return "No videos were found on this source."
        }
    }

    private var canRecoverPhotos: Bool {
        guard let mediaContent = model.mediaContentProfile else {
            return false
        }
        return mediaContent.photoCount > 0 && model.importMediaSelection != .photosOnly
    }

    private var canRecoverVideos: Bool {
        guard let mediaContent = model.mediaContentProfile else {
            return false
        }
        return mediaContent.videoCount > 0 && model.importMediaSelection != .videosOnly
    }

    private var zeroCopyTitle: String {
        if let selectedMediaAvailabilityMessage {
            return selectedMediaAvailabilityMessage
        }
        if model.previewRows.contains(where: { $0.disposition == .excluded }) {
            return "Current choices exclude every matching file"
        }
        if model.previewRows.contains(where: { $0.isKnown }) {
            return "No new files to copy"
        }
        return "No files will be copied"
    }

    private var zeroCopyDetail: String {
        if let mediaContent = model.mediaContentProfile, mediaContent.supportedCount == 0 {
            return "No supported photo or video files were found in this source."
        }
        if model.previewRows.contains(where: { $0.isKnown }) {
            return "These files are already imported, already copied, or already present at the destination."
        }
        return "Change the selected media type, date customization, or destinations to continue."
    }

    private func mediaSelectionTitle(_ selection: ImportMediaSelection) -> String {
        guard let mediaContent = model.mediaContentProfile else {
            return selection.displayTitle
        }
        switch selection {
        case .photosAndVideos:
            return "Photos + Videos"
        case .photosOnly:
            return "Photos (\(mediaContent.photoCount))"
        case .videosOnly:
            return "Videos (\(mediaContent.videoCount))"
        }
    }

    private func mediaContentSummary(_ profile: MediaContentProfile) -> String {
        var parts: [String] = []
        if profile.photoCount > 0 {
            parts.append("\(profile.photoCount) photos")
        }
        if profile.videoCount > 0 {
            parts.append("\(profile.videoCount) videos")
        }
        if profile.sidecarCount > 0 {
            parts.append("\(profile.sidecarCount) support files")
        }
        return parts.isEmpty ? "No supported media" : parts.joined(separator: " · ")
    }

    private func isMediaSelectionAvailable(_ selection: ImportMediaSelection) -> Bool {
        guard let mediaContent = model.mediaContentProfile else {
            return true
        }
        switch selection {
        case .photosAndVideos:
            return mediaContent.photoCount > 0 && mediaContent.videoCount > 0
        case .photosOnly:
            return mediaContent.photoCount > 0
        case .videosOnly:
            return mediaContent.videoCount > 0
        }
    }

    private func filterTitle(_ filter: ImportPreviewFileFilter) -> String {
        "\(filter.title) \(model.previewRows.filter(filter.includes).count)"
    }

    private func sortedRows(_ rows: [ImportPreviewRow]) -> [ImportPreviewRow] {
        rows.enumerated()
            .sorted { lhs, rhs in
                let leftPriority = lhs.element.disposition.attention.rawValue
                let rightPriority = rhs.element.disposition.attention.rawValue
                if leftPriority != rightPriority {
                    return leftPriority > rightPriority
                }
                if lhs.element.willCopy != rhs.element.willCopy {
                    return lhs.element.willCopy
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func destinationText(for row: ImportPreviewRow) -> String {
        if case .rename(let originalPath, let destinationPath, _) = row.disposition {
            return "\(URL(fileURLWithPath: originalPath).lastPathComponent) → \(URL(fileURLWithPath: destinationPath).lastPathComponent)"
        }
        return row.destinationPath ?? row.status
    }

    private func destinationRootTitle(for destination: ImportPreviewDestination) -> String {
        switch destination.root {
        case .library:
            return "Library"
        case .photos:
            return "Photos"
        case .videos:
            return "Videos"
        case .other:
            return "Destination"
        }
    }

    private func spaceText(for requirement: ImportPreviewSpaceRequirement) -> String {
        let required = ByteCountFormatter.string(fromByteCount: requirement.requiredBytes, countStyle: .file)
        guard let availableBytes = requirement.availableBytes else {
            return "Couldn’t check available space · \(required) planned"
        }
        let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        return requirement.isSatisfied
            ? "\(required) needed · \(available) available"
            : "Not enough space: \(required) needed · \(available) available"
    }

    private func visualItems(from rows: [ImportPreviewRow]) -> [ImportPreviewVisualItem] {
        let displayedPairs = rows.compactMap { row in
            row.visualGroupID.map { ($0, row) }
        }
        let displayedGroups = Dictionary(grouping: displayedPairs) { $0.0 }
            .mapValues { $0.map(\.1) }
        let totalPairs = model.previewRows.compactMap { row in
            row.visualGroupID.map { ($0, row) }
        }
        let totalGroupCounts = Dictionary(grouping: totalPairs) { $0.0 }
            .mapValues(\.count)
        var handledGroups: Set<String> = []
        var items: [ImportPreviewVisualItem] = []
        for row in rows {
            guard let groupID = row.visualGroupID else {
                items.append(
                    ImportPreviewVisualItem(id: "file:\(row.id)", rows: [row], totalGroupCount: 1)
                )
                continue
            }
            guard handledGroups.insert(groupID).inserted else {
                continue
            }
            let groupedRows = displayedGroups[groupID] ?? [row]
            let totalGroupCount = totalGroupCounts[groupID] ?? groupedRows.count
            items.append(
                ImportPreviewVisualItem(
                    id: "group:\(groupID)",
                    rows: groupedRows,
                    totalGroupCount: totalGroupCount
                )
            )
        }
        return items
    }

    private func presentSelectedQuickLook() {
        guard let selectedRow else {
            return
        }
        presentQuickLook(for: selectedRow)
    }

    private func presentQuickLook(for row: ImportPreviewRow) {
        let groupRows: [ImportPreviewRow]
        if let groupID = row.visualGroupID {
            groupRows = model.previewRows.filter { $0.visualGroupID == groupID }
        } else {
            groupRows = model.previewRows
        }
        quickLook.present(
            urls: groupRows.map { URL(fileURLWithPath: $0.sourcePath, isDirectory: false) },
            selectedURL: URL(fileURLWithPath: row.sourcePath, isDirectory: false)
        )
    }
}

private struct ImportReviewFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .fontWeight(.semibold)
                Text(readinessText)
                    .font(.caption)
                    .foregroundStyle(model.importReadinessMessage == nil ? Color.secondary : Color.orange)
            }

            Spacer(minLength: 12)

            Button {
                model.importCurrentJob()
            } label: {
                Label(buttonTitle, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canImportPlannedFiles)
            .accessibilityHint(model.importReadinessMessage ?? "Begins copying the reviewed files")
            .accessibilityIdentifier("import.review.copy")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var summary: String {
        let bytes = ByteCountFormatter.string(fromByteCount: model.previewTotals.copyBytes, countStyle: .file)
        let folders = model.previewDestinations.count == 1
            ? "1 folder"
            : "\(model.previewDestinations.count) folders"
        return "\(model.previewTotals.copyFiles) files · \(bytes) · \(folders)"
    }

    private var readinessText: String {
        model.importReadinessMessage ?? "Ready to copy"
    }

    private var buttonTitle: String {
        model.previewTotals.copyFiles == 1 ? "Copy 1 File" : "Copy \(model.previewTotals.copyFiles) Files"
    }
}

private enum ImportPreviewMode: String {
    case list
    case grid
}

private enum ImportPreviewFileFilter: String, CaseIterable, Identifiable {
    case all
    case copy
    case skipped
    case attention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .copy:
            return "Copy"
        case .skipped:
            return "Skipped"
        case .attention:
            return "Attention"
        }
    }

    func includes(_ row: ImportPreviewRow) -> Bool {
        switch self {
        case .all:
            return true
        case .copy:
            return row.willCopy
        case .skipped:
            return !row.willCopy
        case .attention:
            return row.disposition.attention >= .attention
        }
    }
}

private struct PreviewStatusBadge: View {
    let row: ImportPreviewRow

    var body: some View {
        Label(row.status, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel("Status, \(row.status)")
    }

    private var systemImage: String {
        switch row.disposition.attention {
        case .blocking:
            return "exclamationmark.triangle.fill"
        case .attention:
            return "exclamationmark.circle"
        case .informational:
            return "minus.circle"
        case .normal:
            return row.willCopy ? "arrow.down.circle" : "checkmark.circle"
        }
    }

    private var color: Color {
        switch row.disposition.attention {
        case .blocking:
            return .red
        case .attention:
            return .orange
        case .informational:
            return .secondary
        case .normal:
            return row.willCopy ? .green : .secondary
        }
    }
}

private struct ImportPreviewListRow: View {
    let row: ImportPreviewRow
    let destinationText: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            PreviewStatusBadge(row: row)
                .frame(width: 112, alignment: .leading)

            Text(row.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 150, maxWidth: 240, alignment: .leading)

            Text(row.mediaKind.displayTitle)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(destinationText)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(row.willCopy ? .primary : .secondary)
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                .help(row.destinationPath ?? row.sourcePath)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let size = ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)
        return "\(row.filename), \(row.status), \(row.mediaKind.displayTitle), \(size), \(destinationText)"
    }
}

private struct DestinationTreeRow: View {
    let destination: ImportPreviewDestination
    let rootTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(rootTitle)
                    .fontWeight(.medium)
                Text("└─ \(relativePath) · \(destination.fileCount) files · \(bytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(destination.path)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rootTitle), \(relativePath), \(destination.fileCount) files, \(bytes)")
    }

    private var relativePath: String {
        destination.relativePath.isEmpty ? "Root" : destination.relativePath
    }

    private var bytes: String {
        ByteCountFormatter.string(fromByteCount: destination.byteCount, countStyle: .file)
    }
}

private struct ImportPreviewVisualItem: Identifiable {
    let id: String
    let rows: [ImportPreviewRow]
    let totalGroupCount: Int

    var primaryRow: ImportPreviewRow {
        if rows.first?.visualGroupKind == .rawJPEG {
            return rows.first(where: { ["jpg", "jpeg"].contains(URL(fileURLWithPath: $0.filename).pathExtension.lowercased()) })
                ?? rows[0]
        }
        if rows.first?.visualGroupKind == .videoSidecars {
            return rows.first(where: { $0.mediaKind == .video }) ?? rows[0]
        }
        return rows[0]
    }

    var title: String {
        if rows.first?.visualGroupKind == .rawJPEG {
            return URL(fileURLWithPath: primaryRow.filename).deletingPathExtension().lastPathComponent
        }
        return primaryRow.filename
    }

    var subtitle: String {
        switch rows.first?.visualGroupKind {
        case .rawJPEG:
            return rows.count == totalGroupCount
                ? "RAW + JPEG · \(rows.count) files"
                : "\(primaryRow.mediaKind.displayTitle) · \(rows.count) of \(totalGroupCount) paired files"
        case .videoSidecars:
            if rows.count == totalGroupCount {
                return "Video + \(max(0, rows.count - 1)) sidecars"
            }
            return "\(primaryRow.mediaKind.displayTitle) · \(rows.count) of \(totalGroupCount) grouped files"
        case nil:
            return primaryRow.mediaKind.displayTitle
        }
    }

    var status: String {
        let copyCount = rows.filter(\.willCopy).count
        return ImportPreviewGroupDispositionSummary(
            copyCount: copyCount,
            skippedCount: rows.count - copyCount
        ).mixedStatusTitle ?? primaryRow.status
    }
}

private struct ImportPreviewGridCell: View {
    let item: ImportPreviewVisualItem
    let isSelected: Bool
    let thumbnailProvider: ImportThumbnailProvider

    @State private var image: NSImage?
    @State private var requestID: UUID?
    @State private var durationText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.10))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Image(systemName: placeholderImage)
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }

                if item.primaryRow.mediaKind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }

                VStack {
                    HStack {
                        Spacer()
                        Text(item.status)
                            .font(.caption2)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    if let durationText {
                        HStack {
                            Spacer()
                            Text(durationText)
                                .font(.caption2)
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                .padding(6)
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(item.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            resetThumbnailRequest()
        }
        .onChange(of: item.primaryRow.sourcePath) {
            resetThumbnailRequest()
        }
        .onDisappear {
            thumbnailProvider.cancel(requestID)
            requestID = nil
        }
        .task(id: item.primaryRow.sourcePath) {
            durationText = nil
            guard item.primaryRow.mediaKind == .video else {
                return
            }
            durationText = await thumbnailProvider.durationText(for: sourceURL)
        }
    }

    private var sourceURL: URL {
        URL(fileURLWithPath: item.primaryRow.sourcePath, isDirectory: false)
    }

    private var placeholderImage: String {
        switch item.primaryRow.mediaKind {
        case .photo:
            return "photo"
        case .video:
            return "video"
        case .unsupported:
            return "doc"
        }
    }

    private var accessibilityLabel: String {
        "\(item.title), \(item.subtitle), \(item.status)"
    }

    private func startThumbnailRequest() {
        requestID = thumbnailProvider.requestThumbnail(
            for: sourceURL,
            modificationDate: item.primaryRow.modificationDateString,
            size: CGSize(width: 240, height: 180),
            scale: NSScreen.main?.backingScaleFactor ?? 2
        ) { thumbnail in
            image = thumbnail
        }
    }

    private func resetThumbnailRequest() {
        thumbnailProvider.cancel(requestID)
        requestID = nil
        image = nil
        durationText = nil
        startThumbnailRequest()
    }
}

private struct ImportFileInspector: View {
    let row: ImportPreviewRow
    let quickLookAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(row.filename)
                    .font(.headline)
                    .textSelection(.enabled)
                PreviewStatusBadge(row: row)

                inspectorField("Type", value: row.mediaKind.displayTitle)
                inspectorField("Capture Date", value: row.date)
                inspectorField(
                    "Size",
                    value: ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)
                )
                inspectorField("Source", value: row.sourcePath)
                inspectorField("Destination", value: row.destinationPath ?? "No destination")

                if case .rename(let originalPath, let destinationPath, let reason) = row.disposition {
                    inspectorField("Original Name", value: URL(fileURLWithPath: originalPath).lastPathComponent)
                    inspectorField("Resolved Name", value: URL(fileURLWithPath: destinationPath).lastPathComponent)
                    if let reason {
                        inspectorField("Reason", value: reason)
                    }
                }

                Button {
                    quickLookAction()
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("File Details")
    }

    private func inspectorField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension ImportPreviewRow {
    var isPortableKnown: Bool {
        if case .known(let source) = disposition {
            return source == .portableLedger
        }
        return false
    }

    var isKnown: Bool {
        switch disposition {
        case .known, .alreadyExists, .copied:
            return true
        default:
            return false
        }
    }
}

extension ImportMediaSelection {
    var displayTitle: String {
        switch self {
        case .photosAndVideos:
            return "Photos + Videos"
        case .photosOnly:
            return "Photos"
        case .videosOnly:
            return "Videos"
        }
    }
}

extension ImportDestinationLayout {
    var displayTitle: String {
        switch self {
        case .singleLibrary:
            return "Same Library"
        case .separateMediaFolders:
            return "Separate Folders"
        case .footageBackup:
            return "Videos"
        }
    }
}

extension ImportFolderGrouping {
    var displayTitle: String {
        switch self {
        case .byDay:
            return "By Capture Date"
        case .oneShootFolder:
            return "One Shoot"
        }
    }
}

extension MediaKind {
    var displayTitle: String {
        switch self {
        case .photo:
            return "Photo"
        case .video:
            return "Video"
        case .unsupported:
            return "Other"
        }
    }
}
