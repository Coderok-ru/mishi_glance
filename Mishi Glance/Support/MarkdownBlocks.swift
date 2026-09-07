//
//  MarkdownBlocks.swift
//  Mishi Glance
//
//  Заметки к релизу приходят с GitHub в Markdown. SwiftUI умеет только
//  строчную разметку внутри Text, поэтому блоки разбираем сами.
//

import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case quote(String)
    case rule

    /// Разбирает текст на блоки. Строчная разметка (**жирный**, `код`,
    /// ссылки) остаётся внутри — её потом разбирает AttributedString.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if line.hasPrefix("---") || line.hasPrefix("***") {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if line.hasPrefix("#") {
                flushParagraph()
                let hashes = line.prefix { $0 == "#" }.count
                let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.heading(level: hashes, text: text)) }
                continue
            }
            if line.hasPrefix("> ") || line == ">" {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(1))
                    .trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let bullet = bulletText(line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    /// Распознаёт «- пункт», «* пункт» и «1. пункт».
    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        // Нумерованный список: цифры, точка, пробел.
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return String(line.dropFirst(digits.count + 2))
        }
        return nil
    }
}

extension AttributedString {
    /// Строчная разметка без блочной: заголовки и списки уже разобраны.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
