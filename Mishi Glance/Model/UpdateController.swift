//
//  UpdateController.swift
//  Mishi Glance
//
//  Состояние обновления и установка новой версии поверх работающей.
//

import AppKit
import Observation

@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        case installing
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate),
                 (.installing, .installing):
                true
            case (.available(let l), .available(let r)): l.tag == r.tag
            case (.downloading(let l), .downloading(let r)): l == r
            case (.failed(let l), .failed(let r)): l == r
            default: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Показывать ли окно обновления. Тихая фоновая проверка его не поднимает,
    /// пока не найдётся новая версия.
    var isPresenting = false

    @ObservationIgnored private var work: Task<Void, Never>?

    private init() {}

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    // MARK: - Проверка

    /// Ручная проверка: окно показываем всегда, даже если обновлений нет.
    func checkManually() {
        guard !isBusy else { isPresenting = true; return }
        isPresenting = true
        run(silent: false)
    }

    /// Фоновая проверка при запуске, не чаще раза в сутки.
    func checkOnLaunchIfDue() {
        guard AppSettings.automaticUpdateChecks else { return }
        let last = AppSettings.lastUpdateCheck
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        run(silent: true)
    }

    private func run(silent: Bool) {
        work?.cancel()
        state = .checking
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await UpdateChecker.latestNewerRelease()
                AppSettings.lastUpdateCheck = Date()
                guard !Task.isCancelled else { return }
                if let release {
                    self.state = .available(release)
                    self.isPresenting = true
                } else {
                    self.state = .upToDate
                    if silent { self.isPresenting = false }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
                // Молчаливую проверку не показываем: сеть могла просто отсутствовать.
                if silent { self.isPresenting = false }
            }
        }
    }

    func dismiss() {
        isPresenting = false
        if case .installing = state { return }
        work?.cancel()
        state = .idle
    }

    // MARK: - Установка

    func installAvailableUpdate() {
        guard case .available(let release) = state else { return }
        work?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let dmg = try await UpdateChecker.download(release) { fraction in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(fraction)
                    }
                }
                guard !Task.isCancelled else { return }
                self.state = .installing
                try await Self.install(dmgAt: dmg)
                // До сюда не доходим: install перезапускает приложение.
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
                self.isPresenting = true
            }
        }
    }

    /// Проверяет образ, достаёт из него приложение и передаёт замену
    /// внешнему скрипту — сам себя работающий бандл заменить не может.
    private static func install(dmgAt dmg: URL) async throws {
        try UpdateChecker.verifySignature(at: dmg, expectApplication: false)

        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            // Например, приложение лежит в /Applications и принадлежит другому
            // пользователю. Тихо подменить не выйдет — показываем образ.
            NSWorkspace.shared.open(dmg)
            throw UpdateError.destinationNotWritable(parent.path)
        }

        let mount = try mountImage(dmg)
        defer { detach(mount) }

        let source = mount.appendingPathComponent("Mishi Glance.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError.installFailed("в образе нет приложения")
        }

        let staging = dmg.deletingLastPathComponent().appendingPathComponent("staged")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("Mishi Glance.app")
        try FileManager.default.copyItem(at: source, to: staged)

        // Проверяем уже распакованное приложение, а не только контейнер.
        try UpdateChecker.verifySignature(at: staged, expectApplication: true)

        try launchReplacer(staged: staged, destination: destination,
                           cleanup: dmg.deletingLastPathComponent())
        NSApp.terminate(nil)
    }

    private static func mountImage(_ dmg: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let point = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw UpdateError.installFailed("не удалось смонтировать образ") }
        return URL(fileURLWithPath: point)
    }

    private static func detach(_ mount: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mount.path, "-quiet"]
        try? process.run()
    }

    /// Скрипт ждёт выхода приложения, подменяет бандл и запускает новый.
    private static func launchReplacer(staged: URL, destination: URL, cleanup: URL) throws {
        let script = cleanup.appendingPathComponent("replace.sh")
        let body = """
        #!/bin/bash
        # Ждём завершения старой копии, иначе замена бандла на ходу ломает его.
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
            sleep 0.2
        done
        sleep 0.4
        rm -rf "$2"
        /usr/bin/ditto "$1" "$2" || exit 1
        /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
        /usr/bin/open "$2"
        rm -rf "$3"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, staged.path, destination.path, cleanup.path]
        do { try process.run() } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }
}
