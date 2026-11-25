import CryptoKit
import Foundation

// MARK: - Semantic Version

/// Lightweight SemVer parser & comparator supporting optional leading `v`,
/// `major.minor[.patch]`, and pre-release tags (`-beta.1`).
public struct SemanticVersion: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.prerelease = prerelease?.isEmpty == true ? nil : prerelease
    }

    public init?(string raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        // Strip build metadata (+...) if present
        if let plusIndex = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plusIndex])
        }

        let corePart: String
        let prereleasePart: String?
        if let dashIndex = trimmed.firstIndex(of: "-") {
            corePart = String(trimmed[..<dashIndex])
            let pre = String(trimmed[trimmed.index(after: dashIndex)...])
            prereleasePart = pre.isEmpty ? nil : pre
        } else {
            corePart = trimmed
            prereleasePart = nil
        }

        let components = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count) else { return nil }
        guard let major = Int(components[0]), major >= 0,
              let minor = Int(components[1]), minor >= 0 else {
            return nil
        }
        let patch: Int
        if components.count == 3 {
            guard let parsedPatch = Int(components[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prereleasePart
    }

    public var description: String {
        if let prerelease {
            return "\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (_?, nil):
            // Pre-release has lower precedence than the matching stable release.
            return true
        case (nil, _?):
            return false
        case (let lPre?, let rPre?):
            return comparePrerelease(lPre, rPre)
        }
    }

    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> Bool {
        let lParts = lhs.split(separator: ".")
        let rParts = rhs.split(separator: ".")
        for (l, r) in zip(lParts, rParts) {
            if l == r { continue }
            if let lNum = Int(l), let rNum = Int(r) {
                return lNum < rNum
            }
            return l < r
        }
        return lParts.count < rParts.count
    }

    public static func currentAppVersion(from bundle: Bundle = .main, fallback: String = "0.2.6") -> SemanticVersion {
        if let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let parsed = SemanticVersion(string: raw) {
            return parsed
        }
        return SemanticVersion(string: fallback) ?? SemanticVersion(major: 0, minor: 2, patch: 6)
    }

    public static func currentAppBuild(from bundle: Bundle = .main, fallback: String = "8") -> String {
        if let raw = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !raw.isEmpty {
            return raw
        }
        return fallback
    }
}

// MARK: - Release Manifest & Sources

public enum UpdateSourceKind: String, CaseIterable, Codable, Equatable, Sendable {
    case githubRaw
    case chinaMirror
    case jsDelivr
    case githubAPI
}

public enum DownloadChannel: String, Codable, Equatable, Sendable {
    case github
    case mirror
}

public struct ReleaseManifest: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int?
    public let pubDate: String?
    public let minMacOS: String?
    public let releaseUrl: URL
    public let dmgUrl: URL
    public let mirrorDmgUrl: URL?
    public let sha256: String?
    public let sizeBytes: Int64?
    public let notesEn: [String]
    public let notesZh: [String]

    public init(
        version: String,
        build: Int? = nil,
        pubDate: String? = nil,
        minMacOS: String? = nil,
        releaseUrl: URL,
        dmgUrl: URL,
        mirrorDmgUrl: URL? = nil,
        sha256: String? = nil,
        sizeBytes: Int64? = nil,
        notesEn: [String] = [],
        notesZh: [String] = []
    ) {
        self.version = version
        self.build = build
        self.pubDate = pubDate
        self.minMacOS = minMacOS
        self.releaseUrl = releaseUrl
        self.dmgUrl = dmgUrl
        self.mirrorDmgUrl = mirrorDmgUrl
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.notesEn = notesEn
        self.notesZh = notesZh
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case build
        case pubDate
        case minMacOS
        case releaseUrl
        case dmgUrl
        case mirrorDmgUrl
        case sha256
        case sizeBytes
        case notesEn = "notes_en"
        case notesZh = "notes_zh"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        build = try c.decodeIfPresent(Int.self, forKey: .build)
        pubDate = try c.decodeIfPresent(String.self, forKey: .pubDate)
        minMacOS = try c.decodeIfPresent(String.self, forKey: .minMacOS)
        releaseUrl = try c.decode(URL.self, forKey: .releaseUrl)
        dmgUrl = try c.decode(URL.self, forKey: .dmgUrl)
        mirrorDmgUrl = try c.decodeIfPresent(URL.self, forKey: .mirrorDmgUrl)
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        notesEn = try c.decodeIfPresent([String].self, forKey: .notesEn) ?? []
        notesZh = try c.decodeIfPresent([String].self, forKey: .notesZh) ?? []
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(string: version)
    }

    public func isNewer(than currentVersion: SemanticVersion) -> Bool {
        guard let target = semanticVersion else { return false }
        return target > currentVersion
    }

    public func localizedNotes(isChinese: Bool) -> [String] {
        if isChinese {
            return notesZh.isEmpty ? notesEn : notesZh
        }
        return notesEn.isEmpty ? notesZh : notesEn
    }

    /// Parses GitHub's `/releases/latest` JSON payload into a `ReleaseManifest` fallback.
    public static func decodeFromGitHubReleaseAPI(_ data: Data) throws -> ReleaseManifest {
        struct GHAsset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            let size: Int64?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
                case size
            }
        }
        struct GHRelease: Decodable {
            let tagName: String
            let htmlUrl: URL
            let publishedAt: String?
            let body: String?
            let assets: [GHAsset]

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlUrl = "html_url"
                case publishedAt = "published_at"
                case body
                case assets
            }
        }

        let release = try JSONDecoder().decode(GHRelease.self, from: data)
        guard let semver = SemanticVersion(string: release.tagName) else {
            throw UpdateEngineError.invalidManifest
        }
        let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
        guard let dmgAsset else {
            throw UpdateEngineError.invalidManifest
        }
        let sha256 = extractSHA256(from: release.body)
        let bulletLines = extractSummaryBullets(from: release.body)
        return ReleaseManifest(
            version: semver.description,
            build: nil,
            pubDate: release.publishedAt,
            minMacOS: "14.0",
            releaseUrl: release.htmlUrl,
            dmgUrl: dmgAsset.browserDownloadUrl,
            mirrorDmgUrl: nil,
            sha256: sha256,
            sizeBytes: dmgAsset.size,
            notesEn: bulletLines,
            notesZh: bulletLines
        )
    }

    private static func extractSHA256(from body: String?) -> String? {
        guard let body else { return nil }
        let pattern = #"\b[a-fA-F0-9]{64}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let range = Range(match.range, in: body) else {
            return nil
        }
        return String(body[range]).lowercased()
    }

    private static func extractSummaryBullets(from body: String?) -> [String] {
        guard let body else { return [] }
        return body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Security & Trust Policy

public enum UpdateSecurityPolicy {
    private static let allowedDomainSuffixes: [String] = [
        "github.com",
        "githubusercontent.com",
        "jsdelivr.net",
        "jclab.work",
    ]

    /// Strict HTTPS + trusted-host allowlist for manifests, DMG downloads, and HTTP redirects.
    public static func isTrustedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        return allowedDomainSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
    }

    public static func isValidSHA256Hex(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64 else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9")
                || (scalar >= "a" && scalar <= "f")
                || (scalar >= "A" && scalar <= "F")
        }
    }

    /// Streams file bytes in 256 KB chunks into `CryptoKit.SHA256` without loading the DMG into RAM.
    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 262_144)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func verifySHA256(of fileURL: URL, expected: String) throws -> Bool {
        let normalized = expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSHA256Hex(normalized) else { return false }
        let actual = try sha256Hex(of: fileURL)
        return actual == normalized
    }
}

// MARK: - Endpoints & Results

public struct UpdateEndpoint: Equatable, Sendable {
    public let kind: UpdateSourceKind
    public let url: URL

    public init(kind: UpdateSourceKind, url: URL) {
        self.kind = kind
        self.url = url
    }

    public static let defaultPrimary: [UpdateEndpoint] = [
        UpdateEndpoint(
            kind: .githubRaw,
            url: URL(string: "https://raw.githubusercontent.com/BobbyCats/SpinMac/main/docs/latest.json")!
        ),
        UpdateEndpoint(
            kind: .chinaMirror,
            url: URL(string: "https://jclab.work/downloads/spinmac/latest.json")!
        ),
    ]

    public static let defaultFallback: [UpdateEndpoint] = [
        UpdateEndpoint(
            kind: .jsDelivr,
            url: URL(string: "https://cdn.jsdelivr.net/gh/BobbyCats/SpinMac@main/docs/latest.json")!
        ),
        UpdateEndpoint(
            kind: .githubAPI,
            url: URL(string: "https://api.github.com/repos/BobbyCats/SpinMac/releases/latest")!
        ),
    ]
}

public enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate(current: SemanticVersion, latest: SemanticVersion, source: UpdateSourceKind)
    case updateAvailable(manifest: ReleaseManifest, source: UpdateSourceKind)
}

public enum UpdateEngineError: Error, Equatable, Sendable {
    case allSourcesFailed
    case invalidManifest
    case untrustedURL
    case httpStatus(Int)
    case checksumMismatch
    case cancelled
}

public struct DownloadCandidate: Equatable, Sendable {
    public let channel: DownloadChannel
    public let url: URL

    public init(channel: DownloadChannel, url: URL) {
        self.channel = channel
        self.url = url
    }
}

public struct DownloadProgressSnapshot: Equatable, Sendable {
    public let channel: DownloadChannel
    public let fractionCompleted: Double
    public let bytesReceived: Int64
    public let totalBytes: Int64

    public init(channel: DownloadChannel, fractionCompleted: Double, bytesReceived: Int64, totalBytes: Int64) {
        self.channel = channel
        self.fractionCompleted = fractionCompleted
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
    }
}

// MARK: - Multi-Region Update Checker

public typealias ManifestDataFetcher = @Sendable (UpdateEndpoint, TimeInterval) async throws -> Data

/// Pure-Swift, zero-dependency update checker tuned for both overseas and mainland China networks:
/// 1. Races GitHub Raw and the official China HTTPS mirror concurrently so neither region waits on a blocked endpoint.
/// 2. If the faster responder reports an update, returns immediately (~40–150 ms).
/// 3. If the faster responder reports up-to-date, allows a short grace window (default 1.2s) for its sibling in case one mirror lags.
/// 4. Falls back to jsDelivr CDN and GitHub Releases API if both primary endpoints fail.
public struct UpdateChecker: Sendable {
    public let primaryEndpoints: [UpdateEndpoint]
    public let fallbackEndpoints: [UpdateEndpoint]
    public let requestTimeout: TimeInterval
    public let siblingGraceInterval: Duration
    private let fetcher: ManifestDataFetcher

    public init(
        primaryEndpoints: [UpdateEndpoint] = UpdateEndpoint.defaultPrimary,
        fallbackEndpoints: [UpdateEndpoint] = UpdateEndpoint.defaultFallback,
        requestTimeout: TimeInterval = 4.5,
        siblingGraceInterval: Duration = .milliseconds(1200),
        fetcher: ManifestDataFetcher? = nil
    ) {
        self.primaryEndpoints = primaryEndpoints
        self.fallbackEndpoints = fallbackEndpoints
        self.requestTimeout = requestTimeout
        self.siblingGraceInterval = siblingGraceInterval
        self.fetcher = fetcher ?? Self.defaultURLSessionFetcher
    }

    public func check(currentVersion: SemanticVersion) async throws -> UpdateCheckOutcome {
        if let raceWinner = await racePrimaryEndpoints(currentVersion: currentVersion) {
            return evaluate(manifest: raceWinner.manifest, source: raceWinner.source, currentVersion: currentVersion)
        }

        for endpoint in fallbackEndpoints {
            if Task.isCancelled { throw UpdateEngineError.cancelled }
            if let manifest = try? await fetchManifest(from: endpoint) {
                return evaluate(manifest: manifest, source: endpoint.kind, currentVersion: currentVersion)
            }
        }

        throw UpdateEngineError.allSourcesFailed
    }

    /// Selects the fastest download channel first based on which manifest endpoint won the reachability race,
    /// with automatic fallback to the alternate channel.
    public static func orderedDownloadCandidates(
        for manifest: ReleaseManifest,
        winningSource: UpdateSourceKind
    ) -> [DownloadCandidate] {
        var candidates: [DownloadCandidate] = []
        let preferMirrorFirst = (winningSource == .chinaMirror || winningSource == .jsDelivr)

        let rawList: [DownloadCandidate?] = preferMirrorFirst
            ? [
                manifest.mirrorDmgUrl.map { DownloadCandidate(channel: .mirror, url: $0) },
                DownloadCandidate(channel: .github, url: manifest.dmgUrl),
            ]
            : [
                DownloadCandidate(channel: .github, url: manifest.dmgUrl),
                manifest.mirrorDmgUrl.map { DownloadCandidate(channel: .mirror, url: $0) },
            ]

        var seenURLs = Set<URL>()
        for candidate in rawList.compactMap({ $0 }) {
            guard UpdateSecurityPolicy.isTrustedURL(candidate.url) else { continue }
            if seenURLs.insert(candidate.url).inserted {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    // MARK: - Private

    private struct FetchOutcome: Sendable {
        let source: UpdateSourceKind
        let manifest: ReleaseManifest
    }

    private func evaluate(
        manifest: ReleaseManifest,
        source: UpdateSourceKind,
        currentVersion: SemanticVersion
    ) -> UpdateCheckOutcome {
        if manifest.isNewer(than: currentVersion) {
            return .updateAvailable(manifest: manifest, source: source)
        }
        return .upToDate(
            current: currentVersion,
            latest: manifest.semanticVersion ?? currentVersion,
            source: source
        )
    }

    private func racePrimaryEndpoints(currentVersion: SemanticVersion) async -> FetchOutcome? {
        guard !primaryEndpoints.isEmpty else { return nil }

        enum RaceEvent: Sendable {
            case result(FetchOutcome?)
            case graceExpired
        }

        return await withTaskGroup(of: RaceEvent.self, returning: FetchOutcome?.self) { group in
            for endpoint in primaryEndpoints {
                group.addTask {
                    guard let manifest = try? await fetchManifest(from: endpoint) else {
                        return .result(nil)
                    }
                    return .result(FetchOutcome(source: endpoint.kind, manifest: manifest))
                }
            }

            var best: FetchOutcome?
            var remainingFetches = primaryEndpoints.count
            var graceTaskStarted = false

            while remainingFetches > 0 {
                guard let event = await group.next() else { break }
                switch event {
                case .graceExpired:
                    if let best {
                        group.cancelAll()
                        return best
                    }

                case .result(let outcome):
                    remainingFetches -= 1
                    guard let outcome else { continue }

                    // Immediate win if an update is found.
                    if outcome.manifest.isNewer(than: currentVersion) {
                        if let existing = best,
                           let existingVer = existing.manifest.semanticVersion,
                           let newVer = outcome.manifest.semanticVersion,
                           existingVer >= newVer {
                            group.cancelAll()
                            return existing
                        }
                        group.cancelAll()
                        return outcome
                    }

                    // Keep the highest version observed so far.
                    if let existing = best,
                       let existingVer = existing.manifest.semanticVersion,
                       let newVer = outcome.manifest.semanticVersion {
                        if newVer > existingVer {
                            best = outcome
                        }
                    } else {
                        best = outcome
                    }

                    // If first valid response says up-to-date, allow a brief grace window for sibling.
                    if remainingFetches > 0 && !graceTaskStarted {
                        graceTaskStarted = true
                        let grace = siblingGraceInterval
                        group.addTask {
                            try? await Task.sleep(for: grace)
                            return .graceExpired
                        }
                    }
                }
            }

            group.cancelAll()
            return best
        }
    }

    private func fetchManifest(from endpoint: UpdateEndpoint) async throws -> ReleaseManifest {
        guard UpdateSecurityPolicy.isTrustedURL(endpoint.url) else {
            throw UpdateEngineError.untrustedURL
        }
        let data = try await fetcher(endpoint, requestTimeout)
        let manifest: ReleaseManifest
        if endpoint.kind == .githubAPI {
            manifest = try ReleaseManifest.decodeFromGitHubReleaseAPI(data)
        } else {
            manifest = try JSONDecoder().decode(ReleaseManifest.self, from: data)
        }
        guard manifest.semanticVersion != nil,
              UpdateSecurityPolicy.isTrustedURL(manifest.releaseUrl),
              UpdateSecurityPolicy.isTrustedURL(manifest.dmgUrl) else {
            throw UpdateEngineError.invalidManifest
        }
        if let mirror = manifest.mirrorDmgUrl, !UpdateSecurityPolicy.isTrustedURL(mirror) {
            throw UpdateEngineError.untrustedURL
        }
        return manifest
    }

    private static let defaultURLSessionFetcher: ManifestDataFetcher = { endpoint, timeout in
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 1.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        var request = URLRequest(url: endpoint.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SpinMac-Updater/1.0", forHTTPHeaderField: "User-Agent")

        let delegate = TrustedRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateEngineError.allSourcesFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateEngineError.httpStatus(http.statusCode)
        }
        return data
    }
}

// MARK: - Verified DMG Downloader

/// Downloads the notarized DMG with automatic channel fallback (Mirror ↔ GitHub)
/// and mandatory `CryptoKit.SHA256` verification whenever a manifest checksum is present.
public actor UpdateDownloader {
    private var activeTask: URLSessionDownloadTask?
    private var activeSession: URLSession?
    private var isCancelled = false

    public init() {}

    public func cancel() {
        isCancelled = true
        activeTask?.cancel()
        activeSession?.invalidateAndCancel()
        activeTask = nil
        activeSession = nil
    }

    public func downloadVerifiedDMG(
        for manifest: ReleaseManifest,
        winningSource: UpdateSourceKind,
        onProgress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> URL {
        isCancelled = false
        let candidates = UpdateChecker.orderedDownloadCandidates(for: manifest, winningSource: winningSource)
        guard !candidates.isEmpty else {
            throw UpdateEngineError.untrustedURL
        }

        let destinationDir = Self.updatesCacheDirectory()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let safeVersion = manifest.version.replacingOccurrences(of: "/", with: "-")
        let destinationURL = destinationDir.appendingPathComponent("SpinMac-\(safeVersion)-universal.dmg")

        // Reuse an already-downloaded DMG if its SHA-256 already matches cleanly.
        if let expectedSHA = manifest.sha256,
           FileManager.default.fileExists(atPath: destinationURL.path),
           (try? UpdateSecurityPolicy.verifySHA256(of: destinationURL, expected: expectedSHA)) == true {
            onProgress(
                DownloadProgressSnapshot(
                    channel: candidates[0].channel,
                    fractionCompleted: 1.0,
                    bytesReceived: manifest.sizeBytes ?? 0,
                    totalBytes: manifest.sizeBytes ?? 0
                )
            )
            return destinationURL
        }

        var lastError: Error = UpdateEngineError.allSourcesFailed

        for candidate in candidates {
            if isCancelled || Task.isCancelled {
                throw UpdateEngineError.cancelled
            }
            do {
                let downloadedTemp = try await downloadSingle(
                    candidate: candidate,
                    expectedSize: manifest.sizeBytes,
                    onProgress: onProgress
                )
                defer { try? FileManager.default.removeItem(at: downloadedTemp) }

                if let expectedSHA = manifest.sha256, !expectedSHA.isEmpty {
                    let ok = try UpdateSecurityPolicy.verifySHA256(of: downloadedTemp, expected: expectedSHA)
                    guard ok else {
                        throw UpdateEngineError.checksumMismatch
                    }
                }

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: downloadedTemp, to: destinationURL)
                return destinationURL
            } catch {
                if isCancelled || Task.isCancelled {
                    throw UpdateEngineError.cancelled
                }
                lastError = error
                continue
            }
        }

        throw lastError
    }

    private func downloadSingle(
        candidate: DownloadCandidate,
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (DownloadProgressSnapshot) -> Void
    ) async throws -> URL {
        guard UpdateSecurityPolicy.isTrustedURL(candidate.url) else {
            throw UpdateEngineError.untrustedURL
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadSessionDelegate(
                channel: candidate.channel,
                expectedSize: expectedSize,
                onProgress: onProgress,
                completion: { result in
                    continuation.resume(with: result)
                }
            )
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: candidate.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("SpinMac-Updater/1.0", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)
            self.activeSession = session
            self.activeTask = task
            task.resume()
        }
    }

    private static func updatesCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("app.spinmac.SpinMac/Updates", isDirectory: true)
    }
}

// MARK: - URLSession Delegates (Trusted Redirect Enforcement)

private final class TrustedRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, UpdateSecurityPolicy.isTrustedURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let channel: DownloadChannel
    private let expectedSize: Int64?
    private let onProgress: @Sendable (DownloadProgressSnapshot) -> Void
    private let lock = NSLock()
    private var completion: ((Result<URL, Error>) -> Void)?
    private var movedTempURL: URL?

    init(
        channel: DownloadChannel,
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (DownloadProgressSnapshot) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.channel = channel
        self.expectedSize = expectedSize
        self.onProgress = onProgress
        self.completion = completion
    }

    private func finishOnce(with result: Result<URL, Error>, session: URLSession) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()

        session.finishTasksAndInvalidate()
        callback?(result)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, UpdateSecurityPolicy.isTrustedURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (expectedSize ?? 0)
        let fraction: Double = total > 0 ? min(1.0, max(0.0, Double(totalBytesWritten) / Double(total))) : 0.0
        onProgress(
            DownloadProgressSnapshot(
                channel: channel,
                fractionCompleted: fraction,
                bytesReceived: totalBytesWritten,
                totalBytes: total
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finishOnce(with: .failure(UpdateEngineError.httpStatus(http.statusCode)), session: session)
            return
        }

        // URLSession deletes `location` immediately when this callback returns; copy to a temp path we own.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinmac-dl-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: staging)
            lock.lock()
            movedTempURL = staging
            lock.unlock()
            finishOnce(with: .success(staging), session: session)
        } catch {
            finishOnce(with: .failure(error), session: session)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                finishOnce(with: .failure(UpdateEngineError.cancelled), session: session)
            } else {
                finishOnce(with: .failure(error), session: session)
            }
            return
        }
        lock.lock()
        let saved = movedTempURL
        lock.unlock()
        if let saved {
            finishOnce(with: .success(saved), session: session)
        } else {
            finishOnce(with: .failure(UpdateEngineError.allSourcesFailed), session: session)
        }
    }
}
