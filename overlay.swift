import AppKit

let pidFile = "/tmp/claude-voice-zh/overlay.pid"

let args = CommandLine.arguments
guard args.count > 1 else { exit(1) }
let mode = args[1]

if let s = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let p = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
    kill(p, SIGTERM); usleep(150_000)
}
if mode == "hide" { try? FileManager.default.removeItem(atPath: pidFile); exit(0) }
try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidFile, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main!.frame
let size: CGFloat = 44

let window = NSWindow(
    contentRect: NSRect(x: (screen.width - size)/2, y: screen.height - 72, width: size, height: size),
    styleMask: .borderless, backing: .buffered, defer: false
)
window.level = .statusBar
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary]

class V: NSView {
    let mode: String
    var t: Double = 0
    init(mode: String, frame: NSRect) {
        self.mode = mode
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

        if mode == "recording" {
            // 外圈：极淡呼吸光环
            let breath = 0.5 + 0.5 * sin(t * 2.0)
            let outerR: CGFloat = 20 + CGFloat(breath) * 2
            let outerAlpha = 0.04 + breath * 0.06
            NSColor(red: 1, green: 0.25, blue: 0.25, alpha: CGFloat(outerAlpha)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx-outerR, y: cy-outerR, width: outerR*2, height: outerR*2)).fill()

            // 中圈
            let midR: CGFloat = 13 + CGFloat(breath) * 1.5
            let midAlpha = 0.06 + breath * 0.08
            NSColor(red: 1, green: 0.25, blue: 0.25, alpha: CGFloat(midAlpha)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx-midR, y: cy-midR, width: midR*2, height: midR*2)).fill()

            // 核心红点
            let dotR: CGFloat = 6
            let dotAlpha = 0.75 + breath * 0.25
            NSColor(red: 1, green: 0.22, blue: 0.22, alpha: CGFloat(dotAlpha)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx-dotR, y: cy-dotR, width: dotR*2, height: dotR*2)).fill()

        } else {
            // 三个追逐圆点，绕中心旋转
            let r: CGFloat = 10
            for i in 0..<3 {
                let offset = Double(i) * (2.0 * .pi / 3.0)
                let angle = t * 2.5 + offset
                let px = cx + r * CGFloat(cos(angle))
                let py = cy + r * CGFloat(sin(angle))

                // 尾迹
                let tailCount = 4
                for j in 0..<tailCount {
                    let tailAngle = angle - Double(j) * 0.15
                    let tx = cx + r * CGFloat(cos(tailAngle))
                    let ty = cy + r * CGFloat(sin(tailAngle))
                    let tailAlpha = 0.5 * Double(tailCount - j) / Double(tailCount)
                    let tailR: CGFloat = 2.5 - CGFloat(j) * 0.4
                    NSColor(white: 0.85, alpha: CGFloat(tailAlpha)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: tx-tailR, y: ty-tailR, width: tailR*2, height: tailR*2)).fill()
                }

                // 主点
                NSColor(white: 0.92, alpha: 0.9).setFill()
                NSBezierPath(ovalIn: NSRect(x: px-2.8, y: py-2.8, width: 5.6, height: 5.6)).fill()
            }
        }
    }
}

let view = V(mode: mode, frame: NSRect(x: 0, y: 0, width: size, height: size))
window.contentView = view
window.alphaValue = 0
window.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { $0.duration = 0.3; window.animator().alphaValue = 1 }

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    try? FileManager.default.removeItem(atPath: pidFile); app.terminate(nil)
}
signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        try? FileManager.default.removeItem(atPath: pidFile)
        NSApplication.shared.terminate(nil)
    }
}
app.run()
