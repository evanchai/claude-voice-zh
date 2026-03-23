#!/usr/bin/env swift
// overlay.swift — 浮动状态指示器
// 用法: overlay recording | overlay transcribing | overlay hide
// 编译: swiftc overlay.swift -o overlay -framework AppKit

import AppKit

class OverlayWindow: NSWindow {
    init() {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let width: CGFloat = 180
        let height: CGFloat = 40
        let x = (screenWidth - width) / 2
        let y = (NSScreen.main?.frame.height ?? 900) - 80

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
}

class OverlayView: NSView {
    let mode: String
    var dotAlpha: CGFloat = 1.0
    var animTimer: Timer?
    var spinAngle: CGFloat = 0

    init(mode: String, frame: NSRect) {
        self.mode = mode
        super.init(frame: frame)

        if mode == "recording" {
            animTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.dotAlpha = 0.4 + 0.6 * CGFloat(abs(sin(Date().timeIntervalSinceReferenceDate * 2.5)))
                self.needsDisplay = true
            }
        } else if mode == "transcribing" {
            animTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.spinAngle += 5
                self.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)

        // 背景
        NSColor(white: 0.1, alpha: 0.9).setFill()
        path.fill()

        // 边框
        let borderColor = mode == "recording"
            ? NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.6)
            : NSColor(red: 0.3, green: 0.7, blue: 1, alpha: 0.6)
        borderColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        if mode == "recording" {
            // 红色脉冲圆点
            let dotRect = NSRect(x: 16, y: (bounds.height - 12) / 2, width: 12, height: 12)
            NSColor(red: 1, green: 0.2, blue: 0.2, alpha: dotAlpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            // 文字
            let text = "录音中..." as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
            let textSize = text.size(withAttributes: attrs)
            let textPoint = NSPoint(x: 36, y: (bounds.height - textSize.height) / 2)
            text.draw(at: textPoint, withAttributes: attrs)

            // 音量条动画
            for i in 0..<5 {
                let barHeight = CGFloat(6 + Int.random(in: 0...14))
                let barX = CGFloat(120 + i * 8)
                let barY = (bounds.height - barHeight) / 2
                let barRect = NSRect(x: barX, y: barY, width: 4, height: barHeight)
                NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.8).setFill()
                NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()
            }

        } else if mode == "transcribing" {
            // 旋转加载圈
            let centerX: CGFloat = 22
            let centerY: CGFloat = bounds.height / 2
            let radius: CGFloat = 6

            for i in 0..<8 {
                let angle = (CGFloat(i) * 45 + spinAngle) * .pi / 180
                let x = centerX + radius * cos(angle)
                let y = centerY + radius * sin(angle)
                let alpha = CGFloat(i + 1) / 8.0
                NSColor(red: 0.3, green: 0.7, blue: 1, alpha: alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 2, y: y - 2, width: 4, height: 4)).fill()
            }

            // 文字
            let text = "转写中..." as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
            let textSize = text.size(withAttributes: attrs)
            let textPoint = NSPoint(x: 40, y: (bounds.height - textSize.height) / 2)
            text.draw(at: textPoint, withAttributes: attrs)
        }
    }
}

// --- 进程单例管理 ---
let pidFile = "/tmp/claude-voice-zh/overlay.pid"
let stateFile = "/tmp/claude-voice-zh/overlay.state"

func killExisting() {
    if let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
       let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
        kill(pid, SIGTERM)
        usleep(100_000)
    }
}

func savePid() {
    try? "\(ProcessInfo.processInfo.processIdentifier)".write(
        toFile: pidFile, atomically: true, encoding: .utf8
    )
}

func cleanup() {
    try? FileManager.default.removeItem(atPath: pidFile)
    try? FileManager.default.removeItem(atPath: stateFile)
}

// --- Main ---
let args = CommandLine.arguments
guard args.count > 1 else {
    print("用法: overlay recording | transcribing | hide")
    exit(1)
}

let mode = args[1]

if mode == "hide" {
    killExisting()
    cleanup()
    exit(0)
}

// 杀掉之前的 overlay
killExisting()

// 保存 PID
savePid()

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 不在 Dock 显示

let window = OverlayWindow()
let overlayView = OverlayView(mode: mode, frame: window.contentView!.bounds)
window.contentView = overlayView

// 淡入动画
window.alphaValue = 0
window.orderFrontRegardless()
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.2
    window.animator().alphaValue = 1
}

// 30 秒超时自动关闭
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.3
        window.animator().alphaValue = 0
    }) {
        cleanup()
        app.terminate(nil)
    }
}

// 监听 SIGTERM 优雅退出
signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        cleanup()
        NSApplication.shared.terminate(nil)
    }
}

app.run()
