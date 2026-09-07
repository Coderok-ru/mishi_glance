//
//  BatchRenamer.swift
//  Mishi Glance
//
//  Переименование пачкой по шаблону. Порядок берётся тот же, что в окне —
//  как пользователь видит, так и нумеруется.
//

import Foundation

struct RenamePlan: Identifiable, Sendable {
    let source: URL
    let newName: String
    /// Имя конфликтует с другим файлом — применять нельзя.
    var isConflicting = false

    var id: URL { source }
    var oldName: String { source.lastPathComponent }
    var isUnchanged: Bool { newName == oldName }
}

enum BatchRenamer {
    /// Подстановки шаблона. Держим отдельно, чтобы показать подсказку в окне.
    static let tokens: [(token: String, meaning: String)] = [
        ("{имя}", "прежнее имя без расширения"),
        ("{n}", "номер по порядку: 1, 2, 3"),
        ("{nn}", "номер с ведущим нулём: 01, 02"),
        ("{nnn}", "номер тремя знаками: 001, 002"),
        ("{дата}", "дата съёмки, 2026-06-14"),
        ("{время}", "время съёмки, 18-42"),
        ("{камера}", "модель камеры"),
    ]

    /// Строит план переименования, не трогая диск.
    static func plan(for entries: [ImageEntry], template: String,
                     startIndex: Int = 1) -> [RenamePlan] {
        var plans: [RenamePlan] = []
        var taken = Set<String>()

        for (offset, entry) in entries.enumerated() {
            let number = startIndex + offset
            let base = substitute(template, entry: entry, number: number)
            let ext = entry.url.pathExtension
            var candidate = ext.isEmpty ? base : "\(base).\(ext)"

            // Шаблон без номера даст одинаковые имена — разводим суффиксом.
            if taken.contains(candidate.lowercased()) {
                var counter = 2
                repeat {
                    candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                    counter += 1
                } while taken.contains(candidate.lowercased())
            }
            taken.insert(candidate.lowercased())

            // Занято посторонним файлом, который сам не переименовывается.
            let target = entry.url.deletingLastPathComponent()
                .appendingPathComponent(candidate)
            let clash = FileManager.default.fileExists(atPath: target.path)
                && !entries.contains { $0.url.standardizedFileURL == target.standardizedFileURL }

            plans.append(RenamePlan(source: entry.url, newName: candidate,
                                    isConflicting: clash))
        }
        return plans
    }

    private static func substitute(_ template: String, entry: ImageEntry,
                                   number: Int) -> String {
        let metadata = ImageDecoder.metadata(url: entry.url)
        let date = metadata?.captureDate ?? entry.creationDate

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH-mm"

        let camera = [metadata?.cameraMake, metadata?.cameraModel]
            .compactMap { $0 }.joined(separator: " ")

        var result = template
        result = result.replacingOccurrences(
            of: "{имя}", with: entry.url.deletingPathExtension().lastPathComponent)
        result = result.replacingOccurrences(of: "{nnn}", with: String(format: "%03d", number))
        result = result.replacingOccurrences(of: "{nn}", with: String(format: "%02d", number))
        result = result.replacingOccurrences(of: "{n}", with: String(number))
        result = result.replacingOccurrences(of: "{дата}", with: dateFormatter.string(from: date))
        result = result.replacingOccurrences(of: "{время}", with: timeFormatter.string(from: date))
        result = result.replacingOccurrences(
            of: "{камера}", with: camera.isEmpty ? "без-камеры" : camera)

        return sanitize(result)
    }

    /// Убираем то, что файловая система не примет в имени.
    private static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "без-имени" : cleaned
    }

    /// Применяет план. Возвращает, сколько переименовано и что не удалось.
    static func apply(_ plans: [RenamePlan]) -> (renamed: Int, failed: [String]) {
        var renamed = 0
        var failed: [String] = []

        // Двухшаговое переименование через временные имена: иначе перестановка
        // вида a→b, b→a упрётся в занятое имя на первом же шаге.
        var staged: [(temporary: URL, final: URL)] = []
        for plan in plans where !plan.isUnchanged && !plan.isConflicting {
            let directory = plan.source.deletingLastPathComponent()
            let temporary = directory.appendingPathComponent(
                ".mg-rename-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: plan.source, to: temporary)
                staged.append((temporary, directory.appendingPathComponent(plan.newName)))
            } catch {
                failed.append(plan.oldName)
            }
        }
        for (temporary, final) in staged {
            do {
                try FileManager.default.moveItem(at: temporary, to: final)
                renamed += 1
            } catch {
                // Возвращаем как было, чтобы не оставить файл под временным именем.
                try? FileManager.default.moveItem(
                    at: temporary,
                    to: temporary.deletingLastPathComponent()
                        .appendingPathComponent(final.lastPathComponent + ".restored"))
                failed.append(final.lastPathComponent)
            }
        }
        return (renamed, failed)
    }
}
