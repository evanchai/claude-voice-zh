import AppKit
import Foundation

let baseDir = "/tmp/claude-voice-zh"
let pidFile = "\(baseDir)/overlay.pid"
let stateFile = "\(baseDir)/overlay-state"

struct OverlayState: Equatable {
    var mode: String
    var text: String
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func readOverlayState(fallbackMode: String = "recording") -> OverlayState {
    guard let raw = try? String(contentsOfFile: stateFile, encoding: .utf8) else {
        return OverlayState(mode: fallbackMode, text: "")
    }

    let lines = raw.components(separatedBy: .newlines)
    let mode = (lines.first ?? fallbackMode).trimmed
    let text = lines.dropFirst().joined(separator: " ").trimmed

    return OverlayState(
        mode: mode == "transcribing" ? "transcribing" : "recording",
        text: text
    )
}

func writeDefaultState(mode: String) {
    let dirURL = URL(fileURLWithPath: baseDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let content = "\(mode)\n"
    try? content.write(toFile: stateFile, atomically: true, encoding: .utf8)
}

func terminatePreviousOverlay() {
    guard
        let raw = try? String(contentsOfFile: pidFile, encoding: .utf8),
        let pid = Int32(raw.trimmed)
    else {
        return
    }

    kill(pid, SIGTERM)
    usleep(120_000)
}

final class CapsuleView: NSView {
    var state: OverlayState
    var t: Double = 0

    init(state: OverlayState, frame: NSRect) {
        self.state = state
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func displayedText() -> String {
        switch state.mode {
        case "transcribing":
            return state.text.isEmpty ? "正在整理..." : state.text
        default:
            return state.text.isEmpty ? "正在听..." : state.text
        }
    }

    func preferredSize(for visibleFrame: NSRect) -> NSSize {
        let text = displayedText()
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let maxWidth = max(220.0, min(680.0, visibleFrame.width - 40.0))
        let width = min(maxWidth, max(220.0, textWidth + 68.0))
        return NSSize(width: width, height: 46.0)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let radius = rect.height / 2
        let capsulePath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        NSColor(calibratedWhite: 0.06, alpha: 0.86).setFill()
        capsulePath.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.09).setStroke()
        capsulePath.lineWidth = 1
        capsulePath.stroke()

        let shadowRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: radius, yRadius: radius)
        NSColor(calibratedRed: 0.37, green: 0.61, blue: 1.0, alpha: 0.08).setFill()
        shadowPath.fill()

        drawIndicator()
        drawText()
    }

    private func drawIndicator() {
        let center = NSPoint(x: 22, y: bounds.midY)
        let accent = NSColor(calibratedRed: 0.37, green: 0.61, blue: 1.0, alpha: 1.0)

        if state.mode == "transcribing" {
            for index in 0..<3 {
                let phase = t * 4.2 + Double(index) * 0.42
                let lift = sin(phase) * 3.0
                let alpha = 0.45 + (sin(phase) + 1.0) * 0.2
                let rect = NSRect(
                    x: center.x - 10 + CGFloat(index) * 10,
                    y: center.y - 2 + CGFloat(lift),
                    width: 4.5,
                    height: 4.5
                )
                accent.withAlphaComponent(CGFloat(alpha)).setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            return
        }

        let pulse = 0.5 + 0.5 * sin(t * 2.4)
        let glowRadius = 9.0 + pulse * 3.0
        let dotRadius = 3.6

        accent.withAlphaComponent(CGFloat(0.08 + pulse * 0.12)).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
        ).fill()

        accent.withAlphaComponent(CGFloat(0.78 + pulse * 0.22)).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
        ).fill()
    }

    private func drawText() {
        let displayedText = displayedText()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingHead
        paragraph.alignment = .left

        let color: NSColor = state.text.isEmpty && state.mode != "transcribing"
            ? NSColor(calibratedWhite: 1.0, alpha: 0.72)
            : NSColor(calibratedWhite: 1.0, alpha: 0.94)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let textRect = NSRect(x: 38, y: 12, width: bounds.width - 50, height: 22)
        (displayedText as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

final class OverlayController: NSObject {
    private let window: NSWindow
    private let capsuleView: CapsuleView
    private var state: OverlayState
    private var animationTimer: Timer?
    private var stateTimer: Timer?

    init(initialState: OverlayState) {
        state = initialState
        capsuleView = CapsuleView(state: initialState, frame: NSRect(x: 0, y: 0, width: 320, height: 46))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 46),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        super.init()

        window.level = NSWindow.Level.statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = capsuleView
    }

    func start() {
        applyState(animated: false)

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.2
            window.animator().alphaValue = 1
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.capsuleView.t += 1.0 / 60.0
            self.capsuleView.needsDisplay = true
        }

        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.reloadState()
        }
    }

    private func reloadState() {
        let updatedState = readOverlayState(fallbackMode: state.mode)
        guard updatedState != state else {
            return
        }

        state = updatedState
        capsuleView.state = updatedState
        applyState(animated: true)
        capsuleView.needsDisplay = true
    }

    private func activeScreen() -> NSScreen {
        NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main!
    }

    private func applyState(animated: Bool) {
        let screen = activeScreen()
        let visibleFrame = screen.visibleFrame
        let size = capsuleView.preferredSize(for: visibleFrame)
        let frame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 24,
            width: size.width,
            height: size.height
        )

        capsuleView.frame = NSRect(origin: .zero, size: size)

        if animated {
            window.setFrame(frame, display: true, animate: true)
        } else {
            window.setFrame(frame, display: true)
        }
    }
}

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "start"

terminatePreviousOverlay()

if command == "hide" {
    try? FileManager.default.removeItem(atPath: pidFile)
    exit(0)
}

if command == "recording" || command == "transcribing" {
    writeDefaultState(mode: command)
}

try? "\(ProcessInfo.processInfo.processIdentifier)".write(
    toFile: pidFile,
    atomically: true,
    encoding: .utf8
)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        try? FileManager.default.removeItem(atPath: pidFile)
        NSApplication.shared.terminate(nil)
    }
}

let controller = OverlayController(initialState: readOverlayState())
controller.start()
app.run()
