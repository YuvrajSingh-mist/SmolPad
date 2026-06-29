import SwiftUI

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
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(BlockParser.parse(text)) { block in
                BlockView(block: block, textColor: textColor, baseFontSize: baseFontSize)
            }
        }
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
                        .foregroundStyle(textColor.opacity(0.4))
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                }
                Text(block.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.82))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(textColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        case .blockMath:
            LaTeXBlockView(latex: block.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(textColor.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.25), lineWidth: 1)
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
        Text(renderAttributed())
            .foregroundStyle(textColor)
            .textSelection(.enabled)
    }

    private func renderAttributed() -> AttributedString {
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
                    segments.append(InlineSegment(text: plain, font: UIFont.systemFont(ofSize: baseSize)))
                }
            }

            let groups = (1...12).compactMap { idx -> (Int, NSRange)? in
                let r = match.range(at: idx)
                return r.location != NSNotFound ? (idx, r) : nil
            }

            if let (groupIdx, range) = groups.first {
                let captured = nsString.substring(with: range)
                switch groupIdx {
                case 1, 2:
                    segments.append(InlineSegment(text: captured, font: UIFont.monospacedSystemFont(ofSize: max(12, baseSize - 2), weight: .regular), foregroundColor: UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)))
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
                segments.append(InlineSegment(text: trailing, font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
            }
        }

        if segments.isEmpty {
            segments.append(InlineSegment(text: raw, font: UIFont.systemFont(ofSize: baseSize), foregroundColor: defaultColor))
        }

        return segments
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
        switch cmd {
        case "\\sum": return "∑"; case "\\int": return "∫"; case "\\prod": return "∏"
        case "\\infty": return "∞"; case "\\pm": return "±"; case "\\mp": return "∓"
        case "\\times": return "×"; case "\\div": return "÷"; case "\\cdot": return "·"
        case "\\leq": return "≤"; case "\\geq": return "≥"; case "\\neq": return "≠"
        case "\\approx": return "≈"; case "\\equiv": return "≡"; case "\\propto": return "∝"
        case "\\sim": return "∼"; case "\\rightarrow": return "→"; case "\\leftarrow": return "←"
        case "\\Rightarrow": return "⇒"; case "\\Leftarrow": return "⇐"; case "\\Leftrightarrow": return "⇔"
        case "\\to": return "→"; case "\\mapsto": return "↦"; case "\\implies": return "⇒"; case "\\iff": return "⇔"
        case "\\partial": return "∂"; case "\\nabla": return "∇"
        case "\\forall": return "∀"; case "\\exists": return "∃"; case "\\in": return "∈"; case "\\notin": return "∉"
        case "\\subset": return "⊂"; case "\\supset": return "⊃"; case "\\subseteq": return "⊆"; case "\\supseteq": return "⊇"
        case "\\cup": return "∪"; case "\\cap": return "∩"; case "\\emptyset": return "∅"
        case "\\angle": return "∠"; case "\\triangle": return "△"
        case "\\therefore": return "∴"; case "\\because": return "∵"
        case "\\ldots": return "…"; case "\\cdots": return "⋯"; case "\\vdots": return "⋮"; case "\\ddots": return "⋱"
        case "\\hat": return "ˆ"; case "\\bar": return "¯"; case "\\vec": return "→"; case "\\dot": return "˙"; case "\\tilde": return "˜"
        case "\\alpha": return "α"; case "\\beta": return "β"; case "\\gamma": return "γ"; case "\\delta": return "δ"
        case "\\epsilon": return "ε"; case "\\zeta": return "ζ"; case "\\eta": return "η"; case "\\theta": return "θ"
        case "\\iota": return "ι"; case "\\kappa": return "κ"; case "\\lambda": return "λ"; case "\\mu": return "μ"
        case "\\nu": return "ν"; case "\\xi": return "ξ"; case "\\pi": return "π"; case "\\rho": return "ρ"
        case "\\sigma": return "σ"; case "\\tau": return "τ"; case "\\upsilon": return "υ"; case "\\phi": return "φ"
        case "\\chi": return "χ"; case "\\psi": return "ψ"; case "\\omega": return "ω"
        case "\\Gamma": return "Γ"; case "\\Delta": return "Δ"; case "\\Theta": return "Θ"; case "\\Lambda": return "Λ"
        case "\\Xi": return "Ξ"; case "\\Pi": return "Π"; case "\\Sigma": return "Σ"; case "\\Upsilon": return "Υ"
        case "\\Phi": return "Φ"; case "\\Psi": return "Ψ"; case "\\Omega": return "Ω"
        default: return cmd
        }
    }
}

// MARK: - LaTeX Block Renderer

private struct LaTeXBlockView: View {
    let latex: String

    var body: some View {
        if latex.contains("\\frac") {
            fractionView
        } else if latex.contains("\\sqrt") {
            sqrtView
        } else {
            InlineRenderer(text: latex, baseFontSize: 15, textColor: .white)
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 1.0))
                .multilineTextAlignment(.center)
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
