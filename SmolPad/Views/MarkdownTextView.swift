import SwiftUI
import MarkdownUI
import SwiftUIMath

struct MarkdownTextView: View {
    let text: String
    var textColor: Color = .white
    var baseFontSize: CGFloat = 15
    var spacing: CGFloat = 8

    var body: some View {
        let document = AnswerDocumentParser.parse(text)

        VStack(alignment: .leading, spacing: spacing) {
            ForEach(document.blocks) { block in
                switch block.kind {
                case .markdown:
                    Markdown(block.content)
                        .markdownTheme(.smolPadElegant)
                        .markdownTextStyle {
                            FontSize(baseFontSize)
                            ForegroundColor(textColor.opacity(0.94))
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .displayMath:
                    DisplayMathView(
                        latex: block.content,
                        textColor: textColor,
                        baseFontSize: baseFontSize
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DisplayMathView: View {
    let latex: String
    let textColor: Color
    let baseFontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Math(latex)
                .mathTypesettingStyle(.display)
                .mathFont(Math.Font(name: .libertinus, size: max(22, baseFontSize + 6)))
                .foregroundStyle(textColor.opacity(0.96))
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .padding(.vertical, 2)
    }
}

private struct AnswerBlock: Identifiable {
    enum Kind {
        case markdown
        case displayMath
    }

    let id = UUID()
    let kind: Kind
    let content: String
}

private struct AnswerDocument {
    let blocks: [AnswerBlock]
}

private enum AnswerDocumentParser {
    static func parse(_ raw: String) -> AnswerDocument {
        let normalized = MathPreprocessor.normalize(raw)
        let blocks = splitIntoBlocks(normalized)

        if blocks.isEmpty {
            return AnswerDocument(blocks: [
                AnswerBlock(
                    kind: .markdown,
                    content: MarkdownSanitizer.sanitize(normalized)
                )
            ])
        }

        return AnswerDocument(blocks: blocks)
    }

    private static func splitIntoBlocks(_ text: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let start = nextDisplayMathDelimiter(in: text, from: cursor) else {
                appendMarkdown(String(text[cursor...]), to: &blocks)
                break
            }

            appendMarkdown(String(text[cursor..<start.lowerBound]), to: &blocks)

            let contentStart = start.upperBound
            guard let end = text[contentStart...].range(of: "$$") else {
                appendMarkdown(String(text[start.lowerBound...]), to: &blocks)
                break
            }

            let latex = String(text[contentStart..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !latex.isEmpty {
                blocks.append(AnswerBlock(kind: .displayMath, content: latex))
            }
            cursor = end.upperBound
        }

        return blocks
    }

    private static func appendMarkdown(_ text: String, to blocks: inout [AnswerBlock]) {
        let sanitized = MarkdownSanitizer.sanitize(text)
        guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        blocks.append(AnswerBlock(kind: .markdown, content: sanitized))
    }

    private static func nextDisplayMathDelimiter(
        in text: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var cursor = start
        var isInFence = false

        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[cursor..<lineEnd]).trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                isInFence.toggle()
            }

            if !isInFence, let range = text[cursor..<lineEnd].range(of: "$$") {
                return range
            }

            cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }

        return nil
    }
}

private enum MathPreprocessor {
    static func normalize(_ text: String) -> String {
        let normalizedDelimiters = text
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")

        let repaired = repairedBrokenLatexLines(in: normalizedDelimiters)
        return repaired.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private static func repairedBrokenLatexLines(in text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                guard shouldPromoteToDisplayMath(line) else { return line }
                let prefix = markdownPrefix(of: line)
                let contentStart = line.index(line.startIndex, offsetBy: prefix.count)
                let content = line[contentStart...].trimmingCharacters(in: .whitespaces)
                return prefix + "$$\n" + content + "\n$$"
            }
            .joined(separator: "\n")
    }

    private static func shouldPromoteToDisplayMath(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("```"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix(">") else { return false }
        guard !trimmed.contains("$$"), !trimmed.contains("$") else { return false }
        guard trimmed.contains("\\") else { return false }

        let mathSignals = [
            "\\frac", "\\sqrt", "\\sum", "\\int", "\\prod", "\\mathbb",
            "\\arg", "\\max", "\\min", "\\theta", "\\pi", "\\gamma", "\\alpha"
        ]

        let signalCount = mathSignals.filter { trimmed.contains($0) }.count
        let structuralSignals = ["^", "_", "{", "}"].filter { trimmed.contains($0) }.count
        return signalCount > 0 && structuralSignals > 0
    }

    private static func markdownPrefix(of line: String) -> String {
        let leadingWhitespace = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(leadingWhitespace.count))

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("> ") {
            return leadingWhitespace + String(trimmed.prefix(2))
        }

        if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            return leadingWhitespace + String(trimmed[match])
        }

        return leadingWhitespace
    }
}

private enum MarkdownSanitizer {
    static func sanitize(_ text: String) -> String {
        let withoutThinkTags = text
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")

        return inlineMathToReadableText(in: withoutThinkTags)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inlineMathToReadableText(in text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        var isInFence = false

        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[cursor..<lineEnd])
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                isInFence.toggle()
                result += line
            } else if isInFence {
                result += line
            } else {
                result += replaceInlineMath(in: line)
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

    private static func replaceInlineMath(in line: String) -> String {
        var output = ""
        var cursor = line.startIndex

        while cursor < line.endIndex {
            guard let start = line[cursor...].firstIndex(of: "$") else {
                output += String(line[cursor...])
                break
            }

            if start > cursor {
                output += String(line[cursor..<start])
            }

            let contentStart = line.index(after: start)
            guard contentStart < line.endIndex,
                  line[contentStart] != "$",
                  let end = line[contentStart...].firstIndex(of: "$") else {
                output.append("$")
                cursor = contentStart
                continue
            }

            let latex = String(line[contentStart..<end])
            output += LaTeXTextFormatter.prettify(latex)
            cursor = line.index(after: end)
        }

        return output
    }
}

private enum LaTeXTextFormatter {
    private static let replacements: [(String, String)] = [
        ("\\mathbb{E}", "E"),
        ("\\mathbbE", "E"),
        ("\\arg\\max", "arg max"),
        ("\\argmax", "arg max"),
        ("\\arg\\min", "arg min"),
        ("\\argmin", "arg min"),
        ("\\cdot", "·"),
        ("\\times", "×"),
        ("\\div", "÷"),
        ("\\leq", "≤"),
        ("\\geq", "≥"),
        ("\\neq", "≠"),
        ("\\approx", "≈"),
        ("\\infty", "∞"),
        ("\\to", "→"),
        ("\\rightarrow", "→"),
        ("\\leftarrow", "←"),
        ("\\Rightarrow", "⇒"),
        ("\\Leftrightarrow", "⇔"),
        ("\\forall", "∀"),
        ("\\exists", "∃"),
        ("\\in", "∈"),
        ("\\notin", "∉"),
        ("\\subseteq", "⊆"),
        ("\\supseteq", "⊇"),
        ("\\cup", "∪"),
        ("\\cap", "∩"),
        ("\\emptyset", "∅"),
        ("\\sum", "∑"),
        ("\\prod", "∏"),
        ("\\int", "∫"),
        ("\\alpha", "alpha"),
        ("\\beta", "beta"),
        ("\\gamma", "gamma"),
        ("\\delta", "delta"),
        ("\\theta", "theta"),
        ("\\lambda", "lambda"),
        ("\\mu", "mu"),
        ("\\pi", "pi"),
        ("\\sigma", "sigma"),
        ("\\phi", "phi"),
        ("\\omega", "omega")
    ]

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
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        output = output.replacingOccurrences(of: "\\left", with: "")
        output = output.replacingOccurrences(of: "\\right", with: "")
        output = output.replacingOccurrences(of: "\\,", with: " ")
        output = output.replacingOccurrences(of: "\\;", with: " ")
        output = output.replacingOccurrences(of: "\\!", with: "")
        output = output.replacingOccurrences(of: "\\quad", with: " ")
        output = output.replacingOccurrences(of: "\\qquad", with: "  ")
        output = output.replacingOccurrences(of: "\\mathrm{d}", with: "d")
        output = output.replacingOccurrences(of: "\\mathrm", with: "")
        output = replaceFractions(in: output)
        output = replaceSquareRoots(in: output)
        output = replaceScripts(in: output, marker: "^", map: superscripts)
        output = replaceScripts(in: output, marker: "_", map: subscripts)

        for replacement in replacements {
            output = output.replacingOccurrences(of: replacement.0, with: replacement.1)
        }

        output = output
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "  ", with: " ")

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceFractions(in text: String) -> String {
        replaceCommandWithTwoArguments(named: "\\frac", in: text) { numerator, denominator in
            "(\(prettify(numerator)))/(\(prettify(denominator)))"
        }
    }

    private static func replaceSquareRoots(in text: String) -> String {
        replaceCommandWithOneArgument(named: "\\sqrt", in: text) { content in
            "sqrt(\(prettify(content)))"
        }
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
                    result.append(contentsOf: convert(String(text[next]), using: map))
                    index = text.index(after: next)
                    continue
                }
            }

            result.append(current)
            index = text.index(after: index)
        }

        return result
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

    private static func convert(_ string: String, using map: [Character: Character]) -> String {
        String(string.map { map[$0] ?? $0 })
    }
}

private extension Theme {
    static let smolPadElegant = Theme()
        .text {
            ForegroundColor(.white.opacity(0.94))
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .link {
            ForegroundColor(.white.opacity(0.94))
            UnderlineStyle(.single)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.26))
                .markdownMargin(top: .em(0), bottom: .em(0.95))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.34))
                }
                .markdownMargin(top: .em(0.3), bottom: .em(0.9))
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.20))
                }
                .markdownMargin(top: .em(0.25), bottom: .em(0.75))
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
                .markdownMargin(top: .em(0.2), bottom: .em(0.65))
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.white.opacity(0.78))
                    }
            }
            .padding(.vertical, 2)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(.white.opacity(0.92))
            BackgroundColor(Color.white.opacity(0.08))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativePadding(.horizontal, length: .rem(0.9))
                    .relativePadding(.vertical, length: .rem(0.8))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                        ForegroundColor(.white.opacity(0.92))
                    }
            }
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .markdownMargin(top: .em(0.25), bottom: .em(0.9))
        }
        .listItem { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.22))
        }
        .thematicBreak {
            Divider()
                .overlay(Color.white.opacity(0.09))
                .markdownMargin(top: .em(1.0), bottom: .em(1.0))
        }
}
