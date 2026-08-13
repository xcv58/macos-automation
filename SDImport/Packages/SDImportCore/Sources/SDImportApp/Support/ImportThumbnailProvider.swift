@preconcurrency import AppKit
@preconcurrency import AVFoundation
@preconcurrency import QuickLookThumbnailing

@MainActor
final class ImportThumbnailProvider: ObservableObject {
    private enum ThumbnailQuality {
        case low
        case high
    }

    private struct PendingRequest: @unchecked Sendable {
        let id: UUID
        let cacheKey: NSString
        let url: URL
        let size: CGSize
        let scale: CGFloat
        let startsWithHighQuality: Bool
        let update: @MainActor @Sendable (NSImage) -> Void
    }

    private struct ActiveRequest {
        var request: QLThumbnailGenerator.Request
        let pending: PendingRequest
    }

    private let generator = QLThumbnailGenerator.shared
    private let imageCache = NSCache<NSString, NSImage>()
    private let cachedQuality = NSCache<NSString, NSNumber>()
    private var durationCache: [String: String] = [:]
    private var pendingRequests: [PendingRequest] = []
    private var activeRequests: [UUID: ActiveRequest] = [:]
    private let maximumConcurrentRequests = 4

    init() {
        imageCache.totalCostLimit = 64 * 1024 * 1024
        cachedQuality.countLimit = 2_048
    }

    func requestThumbnail(
        for url: URL,
        modificationDate: String,
        size: CGSize,
        scale: CGFloat,
        update: @escaping @MainActor @Sendable (NSImage) -> Void
    ) -> UUID {
        let id = UUID()
        let cacheKey = Self.cacheKey(
            url: url,
            modificationDate: modificationDate,
            size: size,
            scale: scale
        )
        if let cached = imageCache.object(forKey: cacheKey) {
            update(cached)
            if cachedQuality.object(forKey: cacheKey)?.boolValue == true {
                return id
            }
        }

        pendingRequests.append(
            PendingRequest(
                id: id,
                cacheKey: cacheKey,
                url: url,
                size: size,
                scale: scale,
                startsWithHighQuality: imageCache.object(forKey: cacheKey) != nil,
                update: update
            )
        )
        startQueuedRequests()
        return id
    }

    func cancel(_ id: UUID?) {
        guard let id else {
            return
        }
        pendingRequests.removeAll { $0.id == id }
        if let active = activeRequests.removeValue(forKey: id) {
            generator.cancel(active.request)
            startQueuedRequests()
        }
    }

    func cancelAll() {
        pendingRequests.removeAll()
        for active in activeRequests.values {
            generator.cancel(active.request)
        }
        activeRequests.removeAll()
    }

    func durationText(for url: URL) async -> String? {
        let key = url.standardizedFileURL.path
        if let cached = durationCache[key] {
            return cached
        }

        do {
            let duration = try await AVURLAsset(url: url).load(.duration)
            guard duration.isNumeric else {
                return nil
            }
            let totalSeconds = max(0, Int(duration.seconds.rounded()))
            let hours = totalSeconds / 3_600
            let minutes = (totalSeconds % 3_600) / 60
            let seconds = totalSeconds % 60
            let text = hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%d:%02d", minutes, seconds)
            durationCache[key] = text
            return text
        } catch {
            return nil
        }
    }

    private func startQueuedRequests() {
        while activeRequests.count < maximumConcurrentRequests, !pendingRequests.isEmpty {
            let pending = pendingRequests.removeFirst()
            if pending.startsWithHighQuality {
                startHighQualityRequest(pending)
            } else {
                startLowQualityRequest(pending)
            }
        }
    }

    private func startLowQualityRequest(_ pending: PendingRequest) {
        let request = QLThumbnailGenerator.Request(
            fileAt: pending.url,
            size: pending.size,
            scale: pending.scale,
            representationTypes: [.icon, .lowQualityThumbnail]
        )
        activeRequests[pending.id] = ActiveRequest(request: request, pending: pending)
        generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in
                guard let self, self.activeRequests[pending.id] != nil else {
                    return
                }
                if let image {
                    self.cache(image, quality: .low, for: pending)
                    pending.update(image)
                }
                self.startHighQualityRequest(pending)
            }
        }
    }

    private func startHighQualityRequest(_ pending: PendingRequest) {
        let request = QLThumbnailGenerator.Request(
            fileAt: pending.url,
            size: pending.size,
            scale: pending.scale,
            representationTypes: .thumbnail
        )
        activeRequests[pending.id] = ActiveRequest(request: request, pending: pending)
        generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in
                guard let self, self.activeRequests.removeValue(forKey: pending.id) != nil else {
                    return
                }
                if let image {
                    self.cache(image, quality: .high, for: pending)
                    pending.update(image)
                }
                self.startQueuedRequests()
            }
        }
    }

    private func cache(
        _ image: NSImage,
        quality: ThumbnailQuality,
        for pending: PendingRequest
    ) {
        let cost = max(1, Int(pending.size.width * pending.scale * pending.size.height * pending.scale * 4))
        imageCache.setObject(image, forKey: pending.cacheKey, cost: cost)
        cachedQuality.setObject(NSNumber(value: quality == .high), forKey: pending.cacheKey)
    }

    private static func cacheKey(
        url: URL,
        modificationDate: String,
        size: CGSize,
        scale: CGFloat
    ) -> NSString {
        "\(url.standardizedFileURL.path)|\(modificationDate)|\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
    }
}
