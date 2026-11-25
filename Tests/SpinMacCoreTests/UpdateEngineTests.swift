import Foundation
import Testing
@testable import SpinMacCore

@Suite("SpinMac Lightweight Multi-Region Update Engine")
struct UpdateEngineTests {
    private let sampleSHA = "3f257782c3db589c91d1ef701234e2f18f8370d07cd50efce69f2cfd81ded731"

    private func makeManifestJSON(
        version: String,
        dmgUrl: String = "https://github.com/BobbyCats/SpinMac/releases/download/v0.2.6/SpinMac-0.2.6-universal.dmg",
        mirrorDmgUrl: String? = "https://jclab.work/downloads/spinmac/SpinMac-0.2.6-universal.dmg",
        sha256: String? = nil
    ) -> Data {
        let mirrorField = mirrorDmgUrl.map { "\"mirrorDmgUrl\": \"\($0)\"," } ?? ""
        let shaField = sha256 ?? sampleSHA
        let json = """
        {
          "version": "\(version)",
          "build": 8,
          "pubDate": "2026-11-26T04:00:00Z",
          "minMacOS": "14.0",
          "releaseUrl": "https://github.com/BobbyCats/SpinMac/releases/tag/v\(version)",
          "dmgUrl": "\(dmgUrl)",
          \(mirrorField)
          "sha256": "\(shaField)",
          "sizeBytes": 1880000,
          "notes_en": ["Faster bed spin", "Minor polish"],
          "notes_zh": ["翻转响应更快", "细节打磨"]
        }
        """
        return Data(json.utf8)
    }

    @Test("SemanticVersion parses v-prefixes, two/three segments, and compares numerically")
    func semanticVersionOrdering() {
        let v024 = SemanticVersion(string: "0.2.4")!
        let v025 = SemanticVersion(string: "v0.2.5")!
        let v0210 = SemanticVersion(string: "0.2.10")!
        let v10 = SemanticVersion(string: "v1.0")!
        let v025Beta = SemanticVersion(string: "0.2.5-beta.1")!
        let v025Beta2 = SemanticVersion(string: "0.2.5-beta.2")!

        #expect(v024 < v025)
        #expect(v025 < v0210)
        #expect(v0210 < v10)
        #expect(v025Beta < v025Beta2)
        #expect(v025Beta2 < v025)
        #expect(v025 == SemanticVersion(string: "0.2.5"))
        #expect(SemanticVersion(string: "not-a-version") == nil)
        #expect(SemanticVersion(string: "") == nil)
    }

    @Test("UpdateSecurityPolicy enforces HTTPS and strict trusted host allowlist")
    func securityPolicyHostAllowlist() {
        #expect(UpdateSecurityPolicy.isTrustedURL(URL(string: "https://github.com/BobbyCats/SpinMac/releases")!))
        #expect(UpdateSecurityPolicy.isTrustedURL(URL(string: "https://raw.githubusercontent.com/BobbyCats/SpinMac/main/docs/latest.json")!))
        #expect(UpdateSecurityPolicy.isTrustedURL(URL(string: "https://objects.githubusercontent.com/some/asset.dmg")!))
        #expect(UpdateSecurityPolicy.isTrustedURL(URL(string: "https://cdn.jsdelivr.net/gh/BobbyCats/SpinMac@main/docs/latest.json")!))
        #expect(UpdateSecurityPolicy.isTrustedURL(URL(string: "https://jclab.work/downloads/spinmac/latest.json")!))
        #expect(UpdateSecurityPolicy.isTrustedURL(URL(string: "https://cdn.jclab.work/downloads/spinmac/app.dmg")!))

        // Reject HTTP, lookalike suffixes, and untrusted third-party proxies
        #expect(!UpdateSecurityPolicy.isTrustedURL(URL(string: "http://jclab.work/downloads/spinmac/latest.json")!))
        #expect(!UpdateSecurityPolicy.isTrustedURL(URL(string: "https://evil-jclab.work/SpinMac.dmg")!))
        #expect(!UpdateSecurityPolicy.isTrustedURL(URL(string: "https://github.com.evil.example/SpinMac.dmg")!))
        #expect(!UpdateSecurityPolicy.isTrustedURL(URL(string: "https://ghproxy.example/SpinMac.dmg")!))
    }

    @Test("CryptoKit SHA-256 verification matches exact digest and rejects tampered bytes")
    func sha256FileVerification() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinmac-sha-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data("spinmac-notarized-payload".utf8).write(to: tmp)
        let digest = try UpdateSecurityPolicy.sha256Hex(of: tmp)
        #expect(digest.count == 64)
        #expect(try UpdateSecurityPolicy.verifySHA256(of: tmp, expected: digest))
        #expect(try UpdateSecurityPolicy.verifySHA256(of: tmp, expected: digest.uppercased()))
        #expect(try !UpdateSecurityPolicy.verifySHA256(of: tmp, expected: String(repeating: "0", count: 64)))
        #expect(try !UpdateSecurityPolicy.verifySHA256(of: tmp, expected: "not-hex"))
    }

    @Test("GitHub Releases API fallback decodes tag, DMG asset, size, and SHA-256")
    func githubReleaseAPIFallbackDecode() throws {
        let payload = """
        {
          "tag_name": "v0.3.0",
          "html_url": "https://github.com/BobbyCats/SpinMac/releases/tag/v0.3.0",
          "published_at": "2026-12-01T10:00:00Z",
          "body": "## What's New\\n- Native updater\\n- Better bed UX\\n\\nSHA-256: `\(sampleSHA)`",
          "assets": [
            {
              "name": "SpinMac-0.3.0-universal.dmg",
              "browser_download_url": "https://github.com/BobbyCats/SpinMac/releases/download/v0.3.0/SpinMac-0.3.0-universal.dmg",
              "size": 1950000
            }
          ]
        }
        """
        let manifest = try ReleaseManifest.decodeFromGitHubReleaseAPI(Data(payload.utf8))
        #expect(manifest.version == "0.3.0")
        #expect(manifest.sha256 == sampleSHA)
        #expect(manifest.sizeBytes == 1_950_000)
        #expect(manifest.notesEn == ["Native updater", "Better bed UX"])
        #expect(manifest.dmgUrl.lastPathComponent == "SpinMac-0.3.0-universal.dmg")
    }

    @Test("Mainland China scenario: chinaMirror wins race immediately when GitHub is blocked")
    func chinaMirrorWinsWhenGitHubBlocked() async throws {
        let payload = makeManifestJSON(version: "0.2.6")
        let checker = UpdateChecker(
            siblingGraceInterval: .milliseconds(50),
            fetcher: { endpoint, _ in
                switch endpoint.kind {
                case .chinaMirror:
                    return payload
                case .githubRaw:
                    throw URLError(.timedOut)
                default:
                    throw URLError(.cannotConnectToHost)
                }
            }
        )

        let outcome = try await checker.check(currentVersion: SemanticVersion(string: "0.2.5")!)
        guard case .updateAvailable(let manifest, let source) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        #expect(source == .chinaMirror)
        #expect(manifest.version == "0.2.6")

        // Download channel automatically prefers China mirror first, GitHub second
        let candidates = UpdateChecker.orderedDownloadCandidates(for: manifest, winningSource: source)
        #expect(candidates.map(\.channel) == [.mirror, .github])
    }

    @Test("Overseas scenario: githubRaw wins race and orders GitHub DMG first with mirror backup")
    func githubRawWinsOverseas() async throws {
        let payload = makeManifestJSON(version: "0.2.6")
        let checker = UpdateChecker(
            siblingGraceInterval: .milliseconds(50),
            fetcher: { endpoint, _ in
                switch endpoint.kind {
                case .githubRaw:
                    return payload
                case .chinaMirror:
                    try await Task.sleep(for: .milliseconds(250))
                    return payload
                default:
                    throw URLError(.cannotConnectToHost)
                }
            }
        )

        let outcome = try await checker.check(currentVersion: SemanticVersion(string: "0.2.5")!)
        guard case .updateAvailable(let manifest, let source) = outcome else {
            Issue.record("Expected updateAvailable, got \(outcome)")
            return
        }
        #expect(source == .githubRaw)

        let candidates = UpdateChecker.orderedDownloadCandidates(for: manifest, winningSource: source)
        #expect(candidates.map(\.channel) == [.github, .mirror])
    }

    @Test("Sibling grace window catches newer release when faster mirror is slightly stale")
    func siblingGraceCatchesFresherRelease() async throws {
        let stalePayload = makeManifestJSON(version: "0.2.5")
        let freshPayload = makeManifestJSON(version: "0.2.6")

        let checker = UpdateChecker(
            siblingGraceInterval: .milliseconds(400),
            fetcher: { endpoint, _ in
                switch endpoint.kind {
                case .chinaMirror:
                    return stalePayload
                case .githubRaw:
                    try await Task.sleep(for: .milliseconds(40))
                    return freshPayload
                default:
                    throw URLError(.cannotConnectToHost)
                }
            }
        )

        let outcome = try await checker.check(currentVersion: SemanticVersion(string: "0.2.5")!)
        guard case .updateAvailable(let manifest, let source) = outcome else {
            Issue.record("Expected fresher updateAvailable from sibling, got \(outcome)")
            return
        }
        #expect(manifest.version == "0.2.6")
        #expect(source == .githubRaw)
    }

    @Test("Automatic fallback to jsDelivr when both primary endpoints fail")
    func fallbackToJsDelivr() async throws {
        let payload = makeManifestJSON(version: "0.2.5")
        let checker = UpdateChecker(
            siblingGraceInterval: .milliseconds(30),
            fetcher: { endpoint, _ in
                if endpoint.kind == .jsDelivr {
                    return payload
                }
                throw URLError(.notConnectedToInternet)
            }
        )

        let outcome = try await checker.check(currentVersion: SemanticVersion(string: "0.2.5")!)
        guard case .upToDate(let current, let latest, let source) = outcome else {
            Issue.record("Expected upToDate via jsDelivr, got \(outcome)")
            return
        }
        #expect(current == SemanticVersion(string: "0.2.5"))
        #expect(latest == SemanticVersion(string: "0.2.5"))
        #expect(source == .jsDelivr)
    }
}
