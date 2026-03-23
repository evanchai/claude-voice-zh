import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main!
let sf = screen.frame
let vf = screen.visibleFrame  // 排除菜单栏/Dock

// 尺寸
let size: CGFloat = 80
// 屏幕正中央偏上
let centerX = sf.width / 2
let centerY = sf.height / 2 + 60

// ─── 4 个方案并排展示 ───
let gap: CGFloat = 40
let startX = centerX - 1.5 * (size + gap) - size / 2
var windows: [NSWindow] = []

struct Style {
    let label: String
    let color: NSColor       // 录音主色
    let txColor: NSColor     // 转写色
}

let styles: [Style] = [
    // A: 柔白（类 Threads/Typeless）
    Style(label: "A", color: NSColor(white: 0.95, alpha: 1), txColor: NSColor(white: 0.85, alpha: 1)),
    // B: 琥珀暖光
    Style(label: "B", color: NSColor(red: 1.0, green: 0.72, blue: 0.3, alpha: 1), txColor: NSColor(red: 0.9, green: 0.8, blue: 0.5, alpha: 1)),
    // C: 薄荷绿
    Style(label: "C", color: NSColor(red: 0.3, green: 0.95, blue: 0.7, alpha: 1), txColor: NSColor(red: 0.5, green: 0.9, blue: 0.8, alpha: 1)),
    // D: 淡紫
    Style(label: "D", color: NSColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 1), txColor: NSColor(red: 0.75, green: 0.65, blue: 1.0, alpha: 1)),
]

class PreviewView: NSView {
    let style: Style
    let isRec: Bool
    var t: Double = 0
    init(style: Style, isRec: Bool, frame: NSRect) {
        self.style = style
        self.isRec = isRec
        super.init(frame: frame)
        Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            self?.t += 1.0/60
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let cx = b.midX, cy = b.midY

        if isRec {
            let breath = 0.5 + 0.5 * sin(t * 2.0)
            let c = style.color

            // 外层光晕
            let outerR: CGFloat = 24 + CGFloat(breath) * 3
            c.withAlphaComponent(CGFloat(0.04 + breath * 0.06)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx-outerR, y: cy-outerR, width: outerR*2, height: outerR*2)).fill()

            // 中层
            let midR: CGFloat = 15 + CGFloat(breath) * 2
            c.withAlphaComponent(CGFloat(0.08 + breath * 0.1)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx-midR, y: cy-midR, width: midR*2, height: midR*2)).fill()

            // 核心点
            let dotR: CGFloat = 7
            c.withAlphaComponent(CGFloat(0.7 + breath * 0.3)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx-dotR, y: cy-dotR, width: dotR*2, height: dotR*2)).fill()
        } else {
            let c = style.txColor
            let r: CGFloat = 12
            for i in 0..<3 {
                let offset = Double(i) * (2.0 * .pi / 3.0)
                let angle = t * 2.5 + offset
                let px = cx + r * CGFloat(cos(angle))
                let py = cy + r * CGFloat(sin(angle))
                for j in 0..<4 {
                    let ta = angle - Double(j) * 0.15
                    let tx = cx + r * CGFloat(cos(ta))
                    let ty = cy + r * CGFloat(sin(ta))
                    let a = 0.5 * Double(4 - j) / 4.0
                    let tr: CGFloat = 3.0 - CGFloat(j) * 0.5
                    c.withAlphaComponent(CGFloat(a)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: tx-tr, y: ty-tr, width: tr*2, height: tr*2)).fill()
                }
                c.withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: NSRect(x: px-3.2, y: py-3.2, width: 6.4, height: 6.4)).fill()
            }
        }

        // 底部标签
        let label = style.label as NSString
        label.draw(at: NSPoint(x: cx - 4, y: 2), withAttributes: [
            .foregroundColor: NSColor(white: 0.4, alpha: 1),
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ])
    }
}

// 创建 8 个窗口：4 录音 + 4 转写（上下排列）
for (i, style) in styles.enumerated() {
    let x = startX + CGFloat(i) * (size + gap)

    for (rowIdx, isRec) in [true, false].enumerated() {
        let y = topY - CGFloat(rowIdx) * (size + 16)
        let w = NSWindow(
            contentRect: NSRect(x: x, y: y, width: size, height: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        w.level = .statusBar
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.contentView = PreviewView(style: style, isRec: isRec, frame: NSRect(x: 0, y: 0, width: size, height: size))
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; w.animator().alphaValue = 1 }
        windows.append(w)
    }
}

// 8 秒后自动关闭
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { app.terminate(nil) }
app.run()
