import Foundation

/// The two legal documents are Markdown files in `docs/`, bundled into
/// the app as they are and served by the website as they are (D-053):
/// one source of truth. This reads the small subset of Markdown they
/// use — headings, paragraphs, bullet and numbered lists, inline
/// emphasis and links — into blocks a view can lay out. HTML comments
/// are maintainer notes and are dropped.
enum LegalMarkdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case numbered([String])
    }

    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
            if !bullets.isEmpty {
                blocks.append(.bullets(bullets))
                bullets.removeAll()
            }
            if !numbered.isEmpty {
                blocks.append(.numbered(numbered))
                numbered.removeAll()
            }
        }

        for rawLine in stripComments(markdown).components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: text))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty || !numbered.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }
            if let item = numberedItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty { flush() }
                numbered.append(item)
                continue
            }
            // A continuation line belongs to the list item above it when
            // the source indented it; otherwise it is paragraph text.
            if rawLine.hasPrefix("  "), !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + line
            } else if rawLine.hasPrefix("  "), !numbered.isEmpty {
                numbered[numbered.count - 1] += " " + line
            } else {
                if !bullets.isEmpty || !numbered.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// "1. text" → "text".
    private static func numberedItem(_ line: String) -> String? {
        var digits = 0
        for character in line {
            if character.isNumber { digits += 1 } else { break }
        }
        guard digits > 0 else { return nil }
        let rest = line.dropFirst(digits)
        guard rest.hasPrefix(". ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    /// Drops `<!-- … -->`, across lines.
    static func stripComments(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<!--") {
            guard let close = result.range(of: "-->", range: open.upperBound..<result.endIndex) else {
                result.removeSubrange(open.lowerBound..<result.endIndex)
                break
            }
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
    }

    /// The date in an "_Effective date: 10 September 2026._" line.
    static func effectiveDate(in blocks: [Block]) -> Date? {
        for case let .paragraph(text) in blocks {
            let plain = text.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "*", with: "")
            guard let range = plain.range(of: "Effective date:") else { continue }
            var rest = plain[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if let end = rest.firstIndex(where: { $0 == "." || $0 == "," || $0 == ";" }) {
                rest = String(rest[..<end])
            }
            return Self.dayFormatter.date(from: rest)
        }
        return nil
    }

    /// "10 September 2026" — how the documents write the date.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    /// "2026-09-10" — how `Legal.termsVersion` writes it.
    static let versionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// A bundled legal document, parsed.
struct LegalDocument: Equatable {
    var title: String
    var effectiveDate: Date?
    var blocks: [LegalMarkdown.Block]

    init(markdown: String) {
        let blocks = LegalMarkdown.blocks(from: markdown)
        var title = ""
        for case let .heading(level, text) in blocks where level == 1 {
            title = text
            break
        }
        self.title = title
        self.effectiveDate = LegalMarkdown.effectiveDate(in: blocks)
        // The title is the screen's title; it is not repeated in the body.
        self.blocks = blocks.filter { $0 != .heading(level: 1, text: title) }
    }

    /// The effective date as a Terms version ("2026-09-10"), the string
    /// `Legal.termsVersion` must equal.
    var versionKey: String? {
        effectiveDate.map { LegalMarkdown.versionFormatter.string(from: $0) }
    }

    /// The effective date as the document writes it ("10 September
    /// 2026"), in the document's own calendar day — never shifted by the
    /// phone's time zone (D-054).
    var effectiveDateText: String? {
        effectiveDate.map { LegalMarkdown.dayFormatter.string(from: $0) }
    }
}
