import SwiftUI
import UIKit

/// 中国水墨风的配色：宣纸米白、深墨、朱砂点缀。
enum Ink {
    static let paper = dynamic(light: 0xF7F3E9, dark: 0x131211)
    static let paperRaised = dynamic(light: 0xFFFCF4, dark: 0x1C1A18)
    static let paperDeep = dynamic(light: 0xEFE9DA, dark: 0x0D0C0B)
    static let inkText = dynamic(light: 0x241F1B, dark: 0xEDE6D9)
    static let inkSoft = dynamic(light: 0x6B6258, dark: 0x9E9588)
    static let inkFaint = dynamic(light: 0x9C9284, dark: 0x6E675D)
    static let line = dynamic(light: 0xDDD3BE, dark: 0x302C27)
    static let cinnabar = Color(red: 0.72, green: 0.19, blue: 0.14)
    static let cinnabarSoft = Color(red: 0.86, green: 0.42, blue: 0.33)
    static let jade = Color(red: 0.24, green: 0.42, blue: 0.36)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// 水墨背景：纸色渐变 + 两团淡墨
    static func wash(_ useInk: Bool) -> some View {
        ZStack {
            paper.ignoresSafeArea()
            if useInk {
                GeometryReader { geo in
                    Circle()
                        .fill(inkText.opacity(0.05))
                        .frame(width: geo.size.width * 1.1)
                        .blur(radius: 60)
                        .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.30)
                    Circle()
                        .fill(cinnabar.opacity(0.05))
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 70)
                        .offset(x: geo.size.width * 0.45, y: geo.size.height * 0.55)
                }
                .ignoresSafeArea()
            }
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

/// 通用字体
enum InkFont {
    static func title(_ scale: Double = 1) -> Font { .system(size: 20 * scale, weight: .semibold, design: .serif) }
    static func body(_ scale: Double = 1) -> Font { .system(size: 16 * scale) }
    static func small(_ scale: Double = 1) -> Font { .system(size: 13 * scale) }
    static func mono(_ scale: Double = 1) -> Font { .system(size: 13.5 * scale, design: .monospaced) }
    static func seal(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
}

// MARK: - 组件

/// 印章式头像
struct SealAvatar: View {
    var text: String
    var color: Color = Ink.cinnabar
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.12))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(color.opacity(0.55), lineWidth: 1)
            Text(text.isEmpty ? "墨" : String(text.prefix(1)))
                .font(InkFont.seal(size * 0.44))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

struct InkCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Ink.paperRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Ink.line, lineWidth: 0.8)
                    )
            )
    }
}

struct SectionLabel: View {
    var title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Ink.cinnabar)
                    .frame(width: 3, height: 13)
                    .clipShape(Capsule())
                Text(title)
                    .font(InkFont.small(1.05))
                    .fontWeight(.semibold)
                    .foregroundStyle(Ink.inkText)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagChip: View {
    var text: String
    var tint: Color = Ink.inkSoft
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(filled ? tint.opacity(0.16) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 0.7)
            )
            .foregroundStyle(tint)
    }
}

struct EmptyHint: View {
    var title: String
    var detail: String
    var symbol: String = "leaf"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Ink.inkFaint)
            Text(title)
                .font(InkFont.small(1.1))
                .foregroundStyle(Ink.inkSoft)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Ink.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// 复制到剪贴板的按钮
struct CopyButton: View {
    var value: String
    var label: String = "复制"
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                Text(copied ? "已复制" : label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(copied ? Ink.jade : Ink.inkSoft)
        }
        .buttonStyle(.plain)
    }
}

struct LoadingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Ink.inkFaint)
                    .frame(width: 5, height: 5)
                    .opacity(phase > Double(i) * 0.3 ? 1 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}
