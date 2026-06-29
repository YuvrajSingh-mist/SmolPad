import SwiftUI
import MarkdownUI
import SwiftUIMath

// MARK: - Top-level view

/// Renders markdown with LaTeX math into styled SwiftUI views.
/// Supports: **bold**, *italic*, `code`, ```fenced code```,
/// # headers, - bullets, 1. numbered lists, > blockquotes,
/// [links](url), $inline math$, $$block math$$,
/// and common LaTeX: \frac, \sqrt, \sum, \int, Greek letters, etc.
struct MarkdownTextView: View {
    let text: String
    var textColor: Color = .white
    var baseFontSize: CGFloat = 15
    var spacing: CGFloat = 6

    var body: some View {
        RichAnswerRenderer(
            text: text,
            textColor: textColor,
            baseFontSize: baseFontSize,
            spacing: spacing
        )
    }
}

// MARK: - Production Renderer

private struct RichAnswerRenderer: View {
    let text: String
    let textColor: Color
    let baseFontSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(RichAnswerBlockParser.parse(text)) { block in
                switch block.kind {
                case .markdown:
                    MarkdownBlockRenderer(
                        markdown: RawLatexRecovery.normalize(
                            InlineMathNormalizer.normalize(block.content)
                        ),
                        textColor: textColor,
                        baseFontSize: baseFontSize
                    )
                case .math:
                    NativeMathBlock(
                        latex: block.content,
                        baseFontSize: baseFontSize
                    )
                }
            }
        }
    }
}

private struct MarkdownBlockRenderer: View {
    let markdown: String
    let textColor: Color
    let baseFontSize: CGFloat

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.smolPadChat)
            .markdownTextStyle {
                FontSize(baseFontSize)
                ForegroundColor(textColor)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.86))
                ForegroundColor(Color.white.opacity(0.92))
                BackgroundColor(Color.white.opacity(0.08))
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeMathBlock: View {
    let latex: String
    let baseFontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Math(MathDelimiterNormalizer.strip(latex))
                .mathTypesettingStyle(.display)
                .mathFont(Math.Font(name: .libertinus, size: max(20, baseFontSize + 6)))
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private extension Theme {
    static let smolPadChat = Theme()
        .text {
            ForegroundColor(.white.opacity(0.94))
            BackgroundColor(nil)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .link {
            ForegroundColor(Color.white.opacity(0.94))
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 8, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.28))
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 8, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.18))
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 6, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.24))
                .markdownMargin(top: .em(0), bottom: .em(0.85))
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(Color.white.opacity(0.76))
                    }
            }
            .padding(.vertical, 2)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .relativePadding(.horizontal, length: .rem(0.9))
                    .relativePadding(.vertical, length: .rem(0.8))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                    }
            }
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .markdownMargin(top: .em(0.2), bottom: .em(0.9))
        }
        .thematicBreak {
            Divider()
                .overlay(Color.white.opacity(0.09))
                .markdownMargin(top: .em(1.2), bottom: .em(1.2))
        }
}

private struct RichAnswerBlock: Identifiable {
    enum Kind {
        case markdown
        case math
    }

    let id = UUID()
    let kind: Kind
    let content: String
}

private enum RichAnswerBlockParser {
    static func parse(_ raw: String) -> [RichAnswerBlock] {
        let normalized = MathDelimiterNormalizer.normalizeDisplayDelimiters(raw)
        var blocks: [RichAnswerBlock] = []
        var cursor = normalized.startIndex

        while cursor < normalized.endIndex {
            guard let mathStart = nextDisplayMathStart(in: normalized, from: cursor) else {
                appendMarkdown(String(normalized[cursor...]), to: &blocks)
                break
            }

            appendMarkdown(String(normalized[cursor..<mathStart.lowerBound]), to: &blocks)

            let mathContentStart = mathStart.upperBound
            guard let mathEnd = normalized[mathContentStart...].range(of: "$$") else {
                appendMarkdown(String(normalized[mathStart.lowerBound...]), to: &blocks)
                break
            }

            let math = String(normalized[mathContentStart..<mathEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !math.isEmpty {
                blocks.append(RichAnswerBlock(kind: .math, content: math))
            }
            cursor = mathEnd.upperBound
        }

        if blocks.isEmpty && !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(RichAnswerBlock(kind: .markdown, content: raw))
        }

        return blocks
    }

    private static func appendMarkdown(_ markdown: String, to blocks: inout [RichAnswerBlock]) {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blocks.append(RichAnswerBlock(kind: .markdown, content: trimmed))
    }

    private static func nextDisplayMathStart(
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var cursor = start
        var isInFence = false

        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[cursor..<lineEnd])

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInFence.toggle()
            }

            if !isInFence, let mathRange = text[cursor..<lineEnd].range(of: "$$") {
                return mathRange
            }

            cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }

        return nil
    }
}

private enum MathDelimiterNormalizer {
    static func normalizeDisplayDelimiters(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
    }

    static func strip(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\[", with: "")
            .replacingOccurrences(of: "\\]", with: "")
            .replacingOccurrences(of: "$$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum InlineMathNormalizer {
    static func normalize(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
        return replaceInlineMath(in: normalized)
    }

    private static func replaceInlineMath(in text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        var isInFence = false

        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[cursor..<lineEnd])
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                isInFence.toggle()
                result += line
            } else if isInFence {
                result += line
            } else {
                result += replaceInlineMathInLine(line)
            }

            if lineEnd < text.endIndex {
                result.append("\n")
                cursor = text.index(after: lineEnd)
            } else {
                cursor = text.endIndex
            }
        }

        return result
    }

    private static func replaceInlineMathInLine(_ line: String) -> String {
        var output = ""
        var cursor = line.startIndex

        while cursor < line.endIndex {
            guard let start = line[cursor...].firstIndex(of: "$") else {
                output += line[cursor...]
                break
            }

            output += line[cursor..<start]
            let contentStart = line.index(after: start)

            guard contentStart < line.endIndex,
                  line[contentStart] != "$",
                  let end = line[contentStart...].firstIndex(of: "$") else {
                output.append(line[start])
                cursor = contentStart
                continue
            }

            let latex = String(line[contentStart..<end])
            output += LaTeXFormatter.prettify(latex)
            cursor = line.index(after: end)
        }

        return output
    }
}

private enum RawLatexRecovery {
    private static let commandPattern = #"\\[A-Za-z]+"#

    static func normalize(_ markdown: String) -> String {
        var lines: [String] = []
        var isInFence = false

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInFence.toggle()
                lines.append(line)
                continue
            }

            if isInFence || line.contains("$") || !isLikelyBrokenLatexLine(line) {
                lines.append(line)
                continue
            }

            lines.append(normalizeLikelyLatexLine(line))
        }

        return lines.joined(separator: "\n")
    }

    private static func isLikelyBrokenLatexLine(_ line: String) -> Bool {
        let content = markdownContent(of: line)
        guard content.contains("\\") else { return false }

        let commands = latexCommands(in: content)
        if commands.count >= 2 {
            return true
        }

        let strongSignals = [
            "\\frac", "\\sqrt", "\\sum", "\\int", "\\prod",
            "\\mathbb", "\\arg", "\\max", "\\min", "\\pi"
        ]
        if strongSignals.contains(where: content.contains) {
            return true
        }

        return commands.count == 1 && (content.contains("^") || content.contains("_") || content.contains("{"))
    }

    private static func normalizeLikelyLatexLine(_ line: String) -> String {
        let prefix = markdownPrefix(of: line)
        let contentIndex = line.index(line.startIndex, offsetBy: prefix.count)
        let content = String(line[contentIndex...])

        if let colon = content.firstIndex(of: ":") {
            let leading = String(content[..<colon])
            let trailing = String(content[colon...])
            if isLikelyMathFragment(leading) {
                return prefix + LaTeXFormatter.prettify(leading) + trailing
            }
        }

        return prefix + LaTeXFormatter.prettify(content)
    }

    private static func isLikelyMathFragment(_ text: String) -> Bool {
        let commands = latexCommands(in: text)
        if commands.count >= 2 {
            return true
        }
        if commands.count == 1 && (text.contains("^") || text.contains("_")) {
            return true
        }
        return ["\\mathbb", "\\arg", "\\sum", "\\int", "\\pi", "\\frac", "\\sqrt"]
            .contains(where: text.contains)
    }

    private static func latexCommands(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: commandPattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func markdownPrefix(of line: String) -> String {
        let leadingWhitespace = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(leadingWhitespace.count))

        if trimmed.hasPrefix("> ") {
            return leadingWhitespace + "> "
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return leadingWhitespace + String(trimmed.prefix(2))
        }
        if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            return leadingWhitespace + String(trimmed[match])
        }
        return leadingWhitespace
    }

    private static func markdownContent(of line: String) -> String {
        let prefix = markdownPrefix(of: line)
        guard line.count >= prefix.count else { return line }
        let start = line.index(line.startIndex, offsetBy: prefix.count)
        return String(line[start...])
    }
}

private enum LaTeXFormatter {
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "n": "ⁿ", "i": "ⁱ",
        "(": "⁽", ")": "⁾"
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "a": "ₐ", "e": "ₑ",
        "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ",
        "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ",
        "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ", "(": "₍", ")": "₎"
    ]

    static func prettify(_ text: String) -> String {
        var output = text
        output = replaceOperators(in: output)
        output = output.replacingOccurrences(of: "\\left", with: "")
        output = output.replacingOccurrences(of: "\\right", with: "")
        output = output.replacingOccurrences(of: "\\,", with: " ")
        output = output.replacingOccurrences(of: "\\!", with: "")
        output = output.replacingOccurrences(of: "\\;", with: " ")
        output = output.replacingOccurrences(of: "\\qquad", with: "  ")
        output = output.replacingOccurrences(of: "\\quad", with: " ")
        output = output.replacingOccurrences(of: "\\mathrm{d}", with: "d")
        output = output.replacingOccurrences(of: "\\mathrm", with: "")
        output = output.replacingOccurrences(of: "\\text{", with: "{")
        output = replaceFractions(in: output)
        output = replaceSquareRoots(in: output)
        output = replaceIntegrals(in: output)
        output = replaceScripts(in: output, marker: "^", map: superscripts)
        output = replaceScripts(in: output, marker: "_", map: subscripts)
        output = output
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        output = replaceSymbols(in: output)
        output = output.replacingOccurrences(of: "  ", with: " ")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceOperators(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\mathbb{E}", with: "E")
            .replacingOccurrences(of: "\\mathbbE", with: "E")
            .replacingOccurrences(of: "\\mathbb", with: "")
            .replacingOccurrences(of: "\\arg\\max", with: "arg max")
            .replacingOccurrences(of: "\\argmax", with: "arg max")
            .replacingOccurrences(of: "\\arg\\min", with: "arg min")
            .replacingOccurrences(of: "\\argmin", with: "arg min")
            .replacingOccurrences(of: "\\max", with: "max")
            .replacingOccurrences(of: "\\min", with: "min")
            .replacingOccurrences(of: "\\log", with: "log")
            .replacingOccurrences(of: "\\ln", with: "ln")
            .replacingOccurrences(of: "\\sin", with: "sin")
            .replacingOccurrences(of: "\\cos", with: "cos")
            .replacingOccurrences(of: "\\tan", with: "tan")
    }

    private static func replaceSymbols(in text: String) -> String {
        InlineParser.latexCommands.reduce(text) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    private static func replaceFractions(in text: String) -> String {
        replaceCommandWithTwoArguments(named: "\\frac", in: text) { numerator, denominator in
            "(\(prettify(numerator)))/(\(prettify(denominator)))"
        }
    }

    private static func replaceSquareRoots(in text: String) -> String {
        replaceCommandWithOneArgument(named: "\\sqrt", in: text) { content in
            "√(\(prettify(content)))"
        }
    }

    private static func replaceIntegrals(in text: String) -> String {
        let pattern = #"\\int_\{([^}]*)\}\^\{([^}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range).reversed()
        var result = text
        for match in matches {
            guard let lower = Range(match.range(at: 1), in: result),
                  let upper = Range(match.range(at: 2), in: result),
                  let full = Range(match.range, in: result) else { continue }
            let replacement = "∫\(toSubscript(String(result[lower])))\(toSuperscript(String(result[upper])))"
            result.replaceSubrange(full, with: replacement)
        }
        return result
    }

    private static func replaceScripts(
        in text: String,
        marker: Character,
        map: [Character: Character]
    ) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let current = text[index]
            if current == marker {
                let next = text.index(after: index)
                guard next < text.endIndex else { break }

                if text[next] == "{" {
                    let contentStart = text.index(after: next)
                    if let closing = text[contentStart...].firstIndex(of: "}") {
                        let content = String(text[contentStart..<closing])
                        result.append(contentsOf: convert(content, using: map))
                        index = text.index(after: closing)
                        continue
                    }
                } else {
                    result.append(convert(String(text[next]), using: map))
                    index = text.index(after: next)
                    continue
                }
            }

            result.append(current)
            index = text.index(after: index)
        }

        return result
    }

    private static func convert(_ string: String, using map: [Character: Character]) -> String {
        String(string.map { map[$0] ?? $0 })
    }

    private static func toSuperscript(_ string: String) -> String {
        convert(prettify(string), using: superscripts)
    }

    private static func toSubscript(_ string: String) -> String {
        convert(prettify(string), using: subscripts)
    }

    private static func replaceCommandWithOneArgument(
        named command: String,
        in text: String,
        transform: (String) -> String
    ) -> String {
        var result = text
        while let range = result.range(of: command + "{") {
            let start = range.upperBound
            guard let closing = matchingBrace(in: result, from: start) else { break }
            let content = String(result[start..<closing])
            result.replaceSubrange(range.lowerBound..<result.index(after: closing), with: transform(content))
        }
        return result
    }

    private static func replaceCommandWithTwoArguments(
        named command: String,
        in text: String,
        transform: (String, String) -> String
    ) -> String {
        var result = text
        while let firstRange = result.range(of: command + "{") {
            let firstStart = firstRange.upperBound
            guard let firstEnd = matchingBrace(in: result, from: firstStart) else { break }
            let secondOpen = result.index(after: firstEnd)
            guard secondOpen < result.endIndex, result[secondOpen] == "{" else { break }
            let secondStart = result.index(after: secondOpen)
            guard let secondEnd = matchingBrace(in: result, from: secondStart) else { break }
            let first = String(result[firstStart..<firstEnd])
            let second = String(result[secondStart..<secondEnd])
            result.replaceSubrange(firstRange.lowerBound..<result.index(after: secondEnd), with: transform(first, second))
        }
        return result
    }

    private static func matchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

// MARK: - Block Model

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: BlockKind
    let text: String
    let meta: String?

    enum BlockKind {
        case paragraph, heading, bullet, numbered, blockquote
        case codeBlock, blockMath, horizontalRule
    }
}

// MARK: - Block Parser

private enum BlockParser {
    static func parse(_ raw: String) -> [MarkdownBlock] {
        let raw = normalizeMathDelimiters(in: raw)
        var blocks: [MarkdownBlock] = []
        var i = raw.startIndex
        let end = raw.endIndex

        while i < end {
            while i < end, raw[i].isNewline { i = raw.index(after: i) }
            guard i < end else { break }

            let rest = raw[i...]

            if rest.hasPrefix("```") {
                let (code, lang, nextIdx) = extractFencedCode(from: raw, start: i)
                blocks.append(MarkdownBlock(kind: .codeBlock, text: code, meta: lang))
                i = nextIdx
                continue
            }

            if rest.hasPrefix("$$") {
                let (math, nextIdx) = extractBlockMath(from: raw, start: i)
                blocks.append(MarkdownBlock(kind: .blockMath, text: math, meta: nil))
                i = nextIdx
                continue
            }

            if rest.hasPrefix("---") || rest.hasPrefix("***") || rest.hasPrefix("___") {
                blocks.append(MarkdownBlock(kind: .horizontalRule, text: "", meta: nil))
                i = skipLine(from: raw, start: i)
                continue
            }

            let line = extractLine(from: raw, start: i)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i = skipLine(from: raw, start: i)
                continue
            }

            if trimmed.hasPrefix("> ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(MarkdownBlock(kind: .blockquote, text: content, meta: nil))
                i = skipLine(from: raw, start: i)
                continue
            }

            if let numItem = parseNumberedItem(trimmed) {
                blocks.append(MarkdownBlock(kind: .numbered, text: numItem.text, meta: numItem.number))
                i = skipLine(from: raw, start: i)
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(MarkdownBlock(kind: .bullet, text: content, meta: nil))
                i = skipLine(from: raw, start: i)
                continue
            }

            let (para, nextIdx) = extractParagraph(from: raw, start: i)
            if !para.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(MarkdownBlock(kind: .paragraph, text: para, meta: nil))
            }
            i = nextIdx
        }

        if blocks.isEmpty && !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(MarkdownBlock(kind: .paragraph, text: raw, meta: nil))
        }

        return blocks
    }

    private static func normalizeMathDelimiters(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private static func extractLine(from text: String, start: String.Index) -> String {
        let rest = text[start...]
        if let newline = rest.firstIndex(of: "\n") {
            return String(rest[..<newline])
        }
        return String(rest)
    }

    private static func skipLine(from text: String, start: String.Index) -> String.Index {
        let rest = text[start...]
        if let newline = rest.firstIndex(of: "\n") {
            return text.index(after: newline)
        }
        return text.endIndex
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        if line.hasPrefix("### ") { return MarkdownBlock(kind: .heading, text: String(line.dropFirst(4)), meta: "3") }
        if line.hasPrefix("## ")  { return MarkdownBlock(kind: .heading, text: String(line.dropFirst(3)), meta: "2") }
        if line.hasPrefix("# ")   { return MarkdownBlock(kind: .heading, text: String(line.dropFirst(2)), meta: "1") }
        return nil
    }

    private static func parseNumberedItem(_ line: String) -> (text: String, number: String)? {
        guard let regex = try? NSRegularExpression(pattern: "^(\\d+)\\.\\s+(.+)") else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 3,
              let numRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[textRange]), String(line[numRange]))
    }

    private static func extractFencedCode(from text: String, start: String.Index) -> (code: String, lang: String?, next: String.Index) {
        var idx = text.index(start, offsetBy: 3)
        let lang: String?
        if let newline = text[idx...].firstIndex(of: "\n") {
            let raw = String(text[idx..<newline]).trimmingCharacters(in: .whitespaces)
            lang = raw.isEmpty ? nil : raw
            idx = text.index(after: newline)
        } else { lang = nil }

        if let closing = text[idx...].range(of: "\n```") {
            return (String(text[idx..<closing.lowerBound]), lang, text.index(closing.upperBound, offsetBy: 0))
        }
        return (String(text[idx...]), lang, text.endIndex)
    }

    private static func extractBlockMath(from text: String, start: String.Index) -> (math: String, next: String.Index) {
        let idx = text.index(start, offsetBy: 2)
        if let closing = text[idx...].range(of: "$$") {
            let math = String(text[idx..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (math, text.index(closing.upperBound, offsetBy: 0))
        }
        return (String(text[idx...]), text.endIndex)
    }

    private static func extractParagraph(from text: String, start: String.Index) -> (text: String, next: String.Index) {
        var idx = start
        var lines: [String] = []
        while idx < text.endIndex {
            let rest = text[idx...]
            if rest.hasPrefix("```") || rest.hasPrefix("$$") { break }
            let line = extractLine(from: text, start: idx)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { idx = skipLine(from: text, start: idx); break }
            if t.hasPrefix("# ") || t.hasPrefix("## ") || t.hasPrefix("### ") { break }
            if t.hasPrefix("> ") || t.hasPrefix("- ") || t.hasPrefix("* ") { break }
            if t.hasPrefix("---") || t.hasPrefix("***") { break }
            if parseNumberedItem(t) != nil { break }
            lines.append(t)
            idx = skipLine(from: text, start: idx)
        }
        return (lines.joined(separator: "\n"), idx)
    }
}

// MARK: - Block Renderer

private struct BlockView: View {
    let block: MarkdownBlock
    let textColor: Color
    let baseFontSize: CGFloat

    var body: some View {
        switch block.kind {
        case .paragraph:
            InlineRenderer(text: block.text, baseFontSize: baseFontSize, textColor: textColor)
        case .heading:
            let level = Int(block.meta ?? "1") ?? 1
            let size: CGFloat = level == 1 ? baseFontSize + 4 : level == 2 ? baseFontSize + 1 : max(12, baseFontSize - 1)
            InlineRenderer(text: block.text, baseFontSize: size, textColor: textColor).fontWeight(.semibold)
        case .bullet:
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(Color(red: 0.961, green: 0.651, blue: 0.137)).font(.system(size: baseFontSize))
                InlineRenderer(text: block.text, baseFontSize: baseFontSize, textColor: textColor)
            }
        case .numbered:
            HStack(alignment: .top, spacing: 6) {
                Text("\(block.meta ?? "1").")
                    .foregroundStyle(Color(red: 0.961, green: 0.651, blue: 0.137))
                    .font(.system(size: max(12, baseFontSize - 1), weight: .medium, design: .monospaced))
                    .frame(minWidth: 20, alignment: .trailing)
                InlineRenderer(text: block.text, baseFontSize: baseFontSize, textColor: textColor)
            }
        case .blockquote:
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.5))
                    .frame(width: 3).padding(.trailing, 10)
                InlineRenderer(text: block.text, baseFontSize: max(12, baseFontSize - 1), textColor: textColor)
                    .foregroundStyle(textColor.opacity(0.75))
            }
        case .codeBlock:
            VStack(alignment: .leading, spacing: 0) {
                if let lang = block.meta, !lang.isEmpty {
                    Text(lang).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                }
                Text(block.text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.26))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        case .blockMath:
            LaTeXBlockView(latex: block.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color(red: 0.12, green: 0.16, blue: 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.35), lineWidth: 1)
                }
        case .horizontalRule:
            Rectangle().fill(textColor.opacity(0.15)).frame(height: 1).padding(.vertical, 6)
        }
    }
}

// MARK: - Inline Renderer

private struct InlineRenderer: View {
    let text: String
    let baseFontSize: CGFloat
    let textColor: Color

    var body: some View {
        Text(renderAttributed(from: normalizedText))
            .foregroundStyle(textColor)
            .lineSpacing(baseFontSize >= 16 ? 6 : 4)
            .textSelection(.enabled)
    }

    private var normalizedText: String {
        text
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private func renderAttributed(from text: String) -> AttributedString {
        let segments = InlineParser.parse(text, baseSize: baseFontSize, textColor: UIColor(textColor))
        var result = AttributedString()
        for seg in segments {
            var part = AttributedString(seg.text)
            part.foregroundColor = seg.foregroundColor
            part.font = seg.font
            if let bg = seg.backgroundColor { part.backgroundColor = bg }
            result.append(part)
        }
        return result
    }
}

// MARK: - Inline Segment

private struct InlineSegment {
    let text: String
    let font: UIFont
    var foregroundColor: UIColor?
    var backgroundColor: UIColor?
}

// MARK: - Regex-based Inline Parser

private enum InlineParser {
    static let latexCommands: [String: String] = [
        "\\sum": "∑", "\\int": "∫", "\\prod": "∏",
        "\\infty": "∞", "\\pm": "±", "\\mp": "∓",
        "\\times": "×", "\\div": "÷", "\\cdot": "·",
        "\\leq": "≤", "\\geq": "≥", "\\neq": "≠",
        "\\approx": "≈", "\\equiv": "≡", "\\propto": "∝",
        "\\sim": "∼", "\\rightarrow": "→", "\\leftarrow": "←",
        "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔",
        "\\to": "→", "\\mapsto": "↦", "\\implies": "⇒", "\\iff": "⇔",
        "\\partial": "∂", "\\nabla": "∇",
        "\\forall": "∀", "\\exists": "∃", "\\in": "∈", "\\notin": "∉",
        "\\subset": "⊂", "\\supset": "⊃", "\\subseteq": "⊆", "\\supseteq": "⊇",
        "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅",
        "\\angle": "∠", "\\triangle": "△",
        "\\therefore": "∴", "\\because": "∵",
        "\\ldots": "…", "\\cdots": "⋯", "\\vdots": "⋮", "\\ddots": "⋱",
        "\\hat": "ˆ", "\\bar": "¯", "\\vec": "→", "\\dot": "˙", "\\tilde": "˜",
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ",
        "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ", "\\mu": "μ",
        "\\nu": "ν", "\\xi": "ξ", "\\pi": "π", "\\rho": "ρ",
        "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
        "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Upsilon": "Υ",
        "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω"
    ]

    static func parse(_ raw: String, baseSize: CGFloat, textColor: UIColor) -> [InlineSegment] {
        let pattern = #"""
        \$\$(.+?)\$\$|          # display math
        \$(.+?)\$|              # inline math
        \*\*(.+?)\*\*|          # bold
        \*(.+?)\*|              # italic
        `(.+?)`|                # code
        \[(.+?)\]\((.+?)\)|     # link [text](url)
        \\frac\{([^}]+)\}\{([^}]+)\}|   # frac
        \\sqrt\{([^}]+)\}       # sqrt
        """#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.allowCommentsAndWhitespace]) else {
            return [InlineSegment(text: raw, font: UIFont.systemFont(ofSize: baseSize))]
        }

        // Secondary pass: LaTeX symbol → Unicode
        let symbolPattern = #"""
        \\sum|\\int|\\prod|\\infty|\\pm|\\mp|\\times|\\div|\\cdot|
        \\leq|\\geq|\\neq|\\approx|\\equiv|\\propto|\\sim|
        \\rightarrow|\\leftarrow|\\Rightarrow|\\Leftarrow|\\Leftrightarrow|
        \\to|\\mapsto|\\implies|\\iff|\\partial|\\nabla|\\forall|
        \\exists|\\in|\\notin|\\subset|\\supset|\\subseteq|\\supseteq|
        \\cup|\\cap|\\emptyset|\\angle|\\triangle|\\therefore|\\because|
        \\ldots|\\cdots|\\vdots|\\ddots|\\hat|\\bar|\\vec|\\dot|\\tilde|
        \\alpha|\\beta|\\gamma|\\delta|\\epsilon|\\zeta|\\eta|
        \\theta|\\iota|\\kappa|\\lambda|\\mu|\\nu|\\xi|\\pi|
        \\rho|\\sigma|\\tau|\\upsilon|\\phi|\\chi|\\psi|\\omega|
        \\Gamma|\\Delta|\\Theta|\\Lambda|\\Xi|\\Pi|\\Sigma|\\Upsilon|\\Phi|\\Psi|\\Omega
        """#
        guard let symRegex = try? NSRegularExpression(pattern: symbolPattern, options: [.allowCommentsAndWhitespace]) else {
            return parseWithPrimary(raw, baseSize: baseSize, primary: regex, defaultColor: textColor)
        }

        // First pass: primary tokens
        let primarySegments = parseWithPrimary(raw, baseSize: baseSize, primary: regex, defaultColor: textColor)

        // Second pass: convert LaTeX symbols to Unicode within plain segments
        var result: [InlineSegment] = []
        for seg in primarySegments {
            if seg.foregroundColor == nil && seg.backgroundColor == nil {
                // Plain text segment — apply symbol regex
                result.append(contentsOf: parseSymbols(seg.text, baseSize: baseSize, regex: symRegex, defaultColor: textColor))
            } else {
                result.append(seg)
            }
        }
        return result
    }

    private static func parseWithPrimary(_ raw: String, baseSize: CGFloat, primary regex: NSRegularExpression, defaultColor: UIColor) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        let nsString = raw as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        var lastEnd = 0

        regex.enumerateMatches(in: raw, range: fullRange) { match, _, _ in
            guard let match else { return }

            if match.range.location > lastEnd {
                let plain = nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !plain.isEmpty {
                    segments.append(InlineSegment(text: prettifyPlainSegment(plain), font: UIFont.systemFont(ofSize: baseSize)))
                }
            }

            let maxGroupIndex = max(1, match.numberOfRanges - 1)
            let groups = (1...maxGroupIndex).compactMap { idx -> (Int, NSRange)? in
                let r = match.range(at: idx)
                return r.location != NSNotFound ? (idx, r) : nil
            }

            if let (groupIdx, range) = groups.first {
                let captured = nsString.substring(with: range)
                switch groupIdx {
                case 1, 2:
                    segments.append(InlineSegment(text: LaTeXFormatter.prettify(captured), font: UIFont.systemFont(ofSize: max(14, baseSize + 1), weight: .medium), foregroundColor: UIColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 1)))
                case 3:
                    segments.append(InlineSegment(text: captured, font: UIFont.systemFont(ofSize: baseSize, weight: .bold)))
                case 4:
                    segments.append(InlineSegment(text: captured, font: UIFont.italicSystemFont(ofSize: baseSize)))
                case 5:
                    segments.append(InlineSegment(text: captured, font: UIFont.monospacedSystemFont(ofSize: max(11, baseSize - 3), weight: .regular), foregroundColor: UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1), backgroundColor: UIColor(white: 0.20, alpha: 1)))
                case 6, 7:
                    segments.append(InlineSegment(text: captured, font: UIFont.systemFont(ofSize: baseSize), foregroundColor: UIColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 1)))
                case 8:
                    let num = nsString.substring(with: match.range(at: 8))
                    let den = nsString.substring(with: match.range(at: 9))
                    segments.append(InlineSegment(text: "(\(num))/(\(den))", font: UIFont.monospacedSystemFont(ofSize: max(12, baseSize - 2), weight: .regular), foregroundColor: UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)))
                case 10:
                    segments.append(InlineSegment(text: "√(\(captured))", font: UIFont.monospacedSystemFont(ofSize: max(12, baseSize - 2), weight: .regular), foregroundColor: UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)))
                default: break
                }
            }

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsString.length {
            let trailing = nsString.substring(from: lastEnd)
            if !trailing.isEmpty {
                segments.append(InlineSegment(text: prettifyPlainSegment(trailing), font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
            }
        }

        if segments.isEmpty {
            segments.append(InlineSegment(text: raw, font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
        }

        return segments
    }

    private static func prettifyPlainSegment(_ text: String) -> String {
        let looksMathy = text.contains("\\") || text.contains("^") || text.contains("_")
        return looksMathy ? LaTeXFormatter.prettify(text) : text
    }

    private static func parseSymbols(_ text: String, baseSize: CGFloat, regex: NSRegularExpression, defaultColor: UIColor) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        var lastEnd = 0

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            if match.range.location > lastEnd {
                let plain = nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !plain.isEmpty {
                    segments.append(InlineSegment(text: plain, font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
                }
            }
            let rawCmd = nsString.substring(with: match.range)
            let unicode = latexSymbolToUnicode(rawCmd)
            segments.append(InlineSegment(text: unicode, font: UIFont.monospacedSystemFont(ofSize: max(12, baseSize - 1), weight: .regular), foregroundColor: UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)))
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsString.length {
            segments.append(InlineSegment(text: nsString.substring(from: lastEnd), font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
        }
        if segments.isEmpty {
            segments.append(InlineSegment(text: text, font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
        }
        return segments
    }

    private static func latexSymbolToUnicode(_ cmd: String) -> String {
        latexCommands[cmd] ?? cmd
    }
}

// MARK: - LaTeX Block Renderer

private struct LaTeXBlockView: View {
    let latex: String

    var body: some View {
        let pretty = LaTeXFormatter.prettify(latex)

        if latex.contains("\\frac") {
            fractionView
        } else if latex.contains("\\sqrt") {
            sqrtView
        } else {
            Text(pretty)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(Color(red: 0.42, green: 0.82, blue: 1.0))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var fractionView: some View {
        let parts = parseFraction(latex)
        return VStack(spacing: 2) {
            Text(parts.num).font(.system(size: 15, design: .serif)).foregroundStyle(Color(red: 0.3, green: 0.8, blue: 1.0))
            Rectangle().fill(Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.5)).frame(height: 1.5).padding(.horizontal, 4)
            Text(parts.den).font(.system(size: 15, design: .serif)).foregroundStyle(Color(red: 0.3, green: 0.8, blue: 1.0))
        }.padding(.vertical, 4).frame(maxWidth: .infinity)
    }

    private var sqrtView: some View {
        let inner = parseSqrt(latex)
        return HStack(alignment: .top, spacing: 1) {
            Text("√").font(.system(size: 22, design: .serif)).foregroundStyle(Color(red: 0.3, green: 0.8, blue: 1.0))
            Text(inner).font(.system(size: 15, design: .serif)).foregroundStyle(Color(red: 0.3, green: 0.8, blue: 1.0))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.5)).frame(height: 1.5).offset(y: -2)
                }
        }.padding(.vertical, 6).frame(maxWidth: .infinity)
    }

    private func parseFraction(_ s: String) -> (num: String, den: String) {
        guard let start = s.range(of: "\\frac{"),
              let end = s[start.upperBound...].range(of: "}{") else { return ("?", "?") }
        let num = String(s[start.upperBound..<end.lowerBound])
        let rest = s[end.upperBound...]
        return (num, extractBracedContent(String(rest)))
    }

    private func parseSqrt(_ s: String) -> String {
        guard let start = s.range(of: "\\sqrt{") else { return s }
        return extractBracedContent(String(s[start.upperBound...]))
    }

    private func extractBracedContent(_ s: String) -> String {
        var depth = 0
        var result = ""
        for ch in s {
            if ch == "{" { depth += 1; if depth > 1 { result.append(ch) } }
            else if ch == "}" { if depth == 1 { break }; depth -= 1; result.append(ch) }
            else { result.append(ch) }
        }
        return result
    }
}
