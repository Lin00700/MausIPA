import SwiftUI

// MARK: - 思考块拆分

enum Thinking {
    /// 把 <think>…</think> 或 <thinking>…</thinking> 从正文里拆出来
    static func split(_ text: String) -> (visible: String, thinking: String) {
        guard text.contains("<think") else { return (text, "") }
        let pattern = "<think(?:ing)?>([\\s\\S]*?)</think(?:ing)?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, "")
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var thinking: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            if match.numberOfRanges > 1, let inner = Range(match.range(at: 1), in: text) {
                thinking.append(String(text[inner]))
            }
        }
        let visible = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return (visible.trimmingCharacters(in: .whitespacesAndNewlines), thinking.joined(separator: "\n\n"))
    }
}

// MARK: - 轻量 Markdown

enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullets([String])
    case numbers([String])
    case code(String, String)
    case quote(String)
    case rule
}

enum MarkdownParser {
    static func blocks(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language, body.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                flushParagraph()
                var level = 0
                var rest = Substring(trimmed)
                while rest.first == "#" && level < 6 {
                    level += 1
                    rest = rest.dropFirst()
                }
                blocks.append(.heading(level, String(rest).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                var quotes: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quotes.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quotes.joined(separator: "\n")))
                continue
            }

            if let item = bulletItem(trimmed) {
                flushParagraph()
                var items: [String] = [item]
                index += 1
                while index < lines.count, let next = bulletItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.bullets(items))
                continue
            }

            if let item = numberedItem(trimmed) {
                flushParagraph()
                var items: [String] = [item]
                index += 1
                while index < lines.count, let next = numberedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.numbers(items))
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let head = line[line.startIndex..<dot]
        guard !head.isEmpty, head.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.hasPrefix(" ") else { return nil }
        return String(rest).trimmingCharacters(in: .whitespaces)
    }

    /// 行内样式：**粗体**、*斜体*、`代码`、~~删除线~~、[文字](链接)
    static func inline(_ text: String, size: CGFloat, color: Color, weight: Font.Weight = .regular) -> Text {
        let characters = Array(text)
        var pieces: [Text] = []
        var buffer = ""
        var i = 0

        func flush() {
            if !buffer.isEmpty {
                pieces.append(Text(buffer).font(.system(size: size, weight: weight)).foregroundColor(color))
                buffer = ""
            }
        }

        while i < characters.count {
            let character = characters[i]

            if character == "*", i + 1 < characters.count, characters[i + 1] == "*" {
                if let end = find(characters, from: i + 2, token: ["*", "*"]) {
                    flush()
                    let inner = String(characters[(i + 2)..<end])
                    pieces.append(Text(inner).font(.system(size: size, weight: .semibold)).foregroundColor(color))
                    i = end + 2
                    continue
                }
            }

            if character == "~", i + 1 < characters.count, characters[i + 1] == "~" {
                if let end = find(characters, from: i + 2, token: ["~", "~"]) {
                    flush()
                    let inner = String(characters[(i + 2)..<end])
                    pieces.append(Text(inner).font(.system(size: size, weight: weight)).strikethrough().foregroundColor(color.opacity(0.7)))
                    i = end + 2
                    continue
                }
            }

            if character == "`" {
                if let end = characters[(i + 1)...].firstIndex(of: "`") {
                    flush()
                    let inner = String(characters[(i + 1)..<end])
                    pieces.append(Text(inner).font(.system(size: size - 0.5, design: .monospaced)).foregroundColor(Ink.cinnabar))
                    i = end + 1
                    continue
                }
            }

            if character == "*" {
                if let end = characters[(i + 1)...].firstIndex(of: "*") {
                    flush()
                    let inner = String(characters[(i + 1)..<end])
                    pieces.append(Text(inner).font(.system(size: size, weight: weight)).italic().foregroundColor(color))
                    i = end + 1
                    continue
                }
            }

            if character == "[", let close = characters[(i + 1)...].firstIndex(of: "]") {
                if close + 1 < characters.count, characters[close + 1] == "(",
                   let paren = characters[(close + 2)...].firstIndex(of: ")") {
                    flush()
                    let label = String(characters[(i + 1)..<close])
                    pieces.append(Text(label).font(.system(size: size, weight: weight)).underline().foregroundColor(Ink.cinnabar))
                    i = paren + 1
                    continue
                }
            }

            buffer.append(character)
            i += 1
        }
        flush()
        if pieces.isEmpty {
            return Text("").font(.system(size: size))
        }
        var result = pieces[0]
        for piece in pieces.dropFirst() {
            result = result + piece
        }
        return result
    }

    private static func find(_ characters: [Character], from start: Int, token: [Character]) -> Int? {
        guard !token.isEmpty, start < characters.count else { return nil }
        var index = start
        while index + token.count <= characters.count {
            var matches = true
            for offset in 0..<token.count where characters[index + offset] != token[offset] {
                matches = false
                break
            }
            if matches { return index }
            index += 1
        }
        return nil
    }
}

// MARK: - 渲染

struct MarkdownText: View {
    var text: String
    var scale: Double = 1
    var color: Color = Ink.inkText

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MarkdownParser.blocks(text).enumerated()), id: \.offset) { item in
                view(for: item.element)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            let size = max(16, (level == 1 ? 22 : level == 2 ? 19 : 17) * scale)
            MarkdownParser.inline(content, size: size, color: color, weight: .semibold)
                .padding(.top, 4)
        case .paragraph(let content):
            MarkdownParser.inline(content, size: 16 * scale, color: color)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    HStack(alignment: .top, spacing: 7) {
                        Text("·")
                            .font(.system(size: 16 * scale, weight: .bold))
                            .foregroundStyle(Ink.cinnabar)
                        MarkdownParser.inline(pair.element, size: 16 * scale, color: color)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .numbers(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(pair.offset + 1).")
                            .font(.system(size: 14 * scale, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Ink.cinnabar)
                            .padding(.top, 1)
                        MarkdownParser.inline(pair.element, size: 16 * scale, color: color)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let language, let body):
            CodeBlockView(language: language, code: body, scale: scale)
        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Ink.cinnabar.opacity(0.5))
                    .frame(width: 2)
                MarkdownParser.inline(content, size: 15 * scale, color: Ink.inkSoft)
                    .lineSpacing(3)
            }
            .padding(.vertical, 2)
        case .rule:
            Rectangle()
                .fill(Ink.line)
                .frame(height: 0.8)
                .padding(.vertical, 4)
        }
    }
}

struct CodeBlockView: View {
    var language: String
    var code: String
    var scale: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Ink.inkFaint)
                Spacer()
                CopyButton(value: code)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13 * scale, design: .monospaced))
                    .foregroundStyle(Ink.inkText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Ink.paperDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Ink.line, lineWidth: 0.8)
        )
    }
}
