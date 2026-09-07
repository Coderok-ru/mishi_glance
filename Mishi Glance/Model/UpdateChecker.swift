//
//  UpdateChecker.swift
//  Mishi Glance
//
//  Проверка релизов на GitHub, загрузка образа и проверка его подписи.
//  Sparkle не используется: ТЗ запрещает внешние зависимости, а вся нужная
//  логика умещается в один файл поверх Releases API.
//

import AppKit
import Foundation

/// Версия вида 1.2.3 для сравнения «больше — новее».
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init(_ string: String) {
        let cleaned = string.hasPrefix("v") ? String(string.dropFirst()) : string
        parts = cleaned
            .split(whereSeparator: { !$0.isNumber })
            .map { Int($0) ?? 0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0 ..< max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct ReleaseInfo: Sendable {
    let version: AppVersion
    let tag: String
    let title: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL
    let byteCount: Int
}

enum UpdateError: LocalizedError {
    case network(String)
    case noBuildableAsset
    case badResponse(Int)
    case untrustedDownload(String)
    case destinationNotWritable(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let detail): "Не удалось связаться с GitHub: \(detail)"
        case .noBuildableAsset: "В релизе нет установочного образа"
        case .badResponse(let code): "GitHub ответил кодом \(code)"
        case .untrustedDownload(let detail): "Проверка подписи не пройдена: \(detail)"
        case .destinationNotWritable(let path): "Нет прав на запись в \(path)"
        case .installFailed(let detail): "Не удалось установить обновление: \(detail)"
        }
    }
}

enum UpdateChecker {
    static let repository = "Coderok-ru/mishi_glance"
    /// Обновление принимается только за подписью этой команды.
    static let expectedTeamID = "FKD7Y4FR88"

    static var currentVersion: AppVersion {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
    }

    // MARK: - Запрос к GitHub

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            let size: Int

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, draft, prerelease, assets
            case htmlURL = "html_url"
        }
    }

    /// Возвращает последний релиз, если он новее установленной версии.
    static func latestNewerRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: URL(string:
            "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Mishi Glance", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse(0)
        }
        // 404 — релизов ещё нет, это не ошибка.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw UpdateError.badResponse(http.statusCode) }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }

        let version = AppVersion(release.tagName)
        guard version > currentVersion else { return nil }

        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              let downloadURL = URL(string: asset.browserDownloadURL),
              let pageURL = URL(string: release.htmlURL)
        else { throw UpdateError.noBuildableAsset }

        // Ссылка обязана быть https и вести на GitHub.
        guard downloadURL.scheme == "https",
              let host = downloadURL.host,
              host.hasSuffix("github.com") || host.hasSuffix("githubusercontent.com")
        else { throw UpdateError.untrustedDownload("подозрительный адрес загрузки") }

        return ReleaseInfo(
            version: version,
            tag: release.tagName,
            title: release.name ?? release.tagName,
            notes: release.body ?? "",
            pageURL: pageURL,
            downloadURL: downloadURL,
            byteCount: asset.size
        )
    }

    // MARK: - Загрузка

    /// Качает образ во временную папку, сообщая долю выполненного.
    static func download(_ release: ReleaseInfo,
                         progress: @Sendable @escaping (Double) -> Void) async throws -> URL {
        var request = URLRequest(url: release.downloadURL)
        request.setValue("Mishi Glance", forHTTPHeaderField: "User-Agent")

        let (stream, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (stream, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let expected = release.byteCount > 0 ? release.byteCount : Int(http.expectedContentLength)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MishiGlanceUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("Mishi Glance \(release.version).dmg")

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else {
            throw UpdateError.installFailed("не удалось создать файл загрузки")
        }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 18)
        var received = 0
        var lastReported = 0.0

        for try await byte in stream {
            buffer.append(byte)
            if buffer.count >= 1 << 18 {
                try handle.write(contentsOf: buffer)
                received += buffer.count
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    let fraction = min(Double(received) / Double(expected), 1)
                    if fraction - lastReported > 0.01 {
                        lastReported = fraction
                        progress(fraction)
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += buffer.count
        }
        progress(1)

        guard received > 0 else { throw UpdateError.installFailed("пустая загрузка") }
        return destination
    }

    // MARK: - Проверка подписи

    /// Пускаем дальше только то, что подписано нашей командой. Без этой
    /// проверки автообновление стало бы каналом подмены приложения.
    static func verifySignature(at url: URL, expectApplication: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", "--verbose=2", url.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        do { try process.run() } catch {
            throw UpdateError.untrustedDownload("codesign не запустился")
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.untrustedDownload(output.isEmpty ? "подпись недействительна" : output)
        }

        let authority = try signingAuthority(at: url)
        guard authority.teamID == expectedTeamID else {
            throw UpdateError.untrustedDownload("чужая команда разработчика: \(authority.teamID)")
        }
        guard authority.isDeveloperID else {
            throw UpdateError.untrustedDownload("подпись не Developer ID")
        }
        if expectApplication, !authority.hasHardenedRuntime {
            throw UpdateError.untrustedDownload("приложение без hardened runtime")
        }
    }

    private static func signingAuthority(at url: URL)
        throws -> (teamID: String, isDeveloperID: Bool, hasHardenedRuntime: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dvv", url.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        do { try process.run() } catch {
            throw UpdateError.untrustedDownload("codesign не запустился")
        }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        var teamID = ""
        var isDeveloperID = false
        var hardened = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                teamID = String(line.dropFirst("TeamIdentifier=".count))
            }
            if line.hasPrefix("Authority=Developer ID Application") { isDeveloperID = true }
            if line.contains("flags=") && line.contains("runtime") { hardened = true }
        }
        return (teamID, isDeveloperID, hardened)
    }
}
