import AVFoundation
import Speech
import Foundation

// --- Parse arguments ---
var langInput = "zh"
var stateFile = "/tmp/claude-voice-zh/overlay-state"
var resultFile = "/tmp/claude-voice-zh/result.txt"
var audioFile = "/tmp/claude-voice-zh/recording.wav"

var i = 1
while i < CommandLine.arguments.count {
    switch CommandLine.arguments[i] {
    case "--lang" where i + 1 < CommandLine.arguments.count:
        langInput = CommandLine.arguments[i + 1]; i += 2
    case "--state" where i + 1 < CommandLine.arguments.count:
        stateFile = CommandLine.arguments[i + 1]; i += 2
    case "--result" where i + 1 < CommandLine.arguments.count:
        resultFile = CommandLine.arguments[i + 1]; i += 2
    case "--audio" where i + 1 < CommandLine.arguments.count:
        audioFile = CommandLine.arguments[i + 1]; i += 2
    default:
        i += 1
    }
}

// --- Locale mapping ---
let localeMap: [String: String] = [
    "zh": "zh_CN", "en": "en_US", "ja": "ja_JP",
    "ko": "ko_KR", "fr": "fr_FR", "de": "de_DE", "es": "es_ES",
]
let localeId = localeMap[langInput] ?? langInput

guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) else {
    fputs("error: unsupported locale \(localeId)\n", stderr)
    exit(1)
}

guard speechRecognizer.isAvailable else {
    fputs("error: speech recognizer unavailable for \(localeId)\n", stderr)
    exit(1)
}

// --- Authorization ---
let sem = DispatchSemaphore(value: 0)
var authOK = false

SFSpeechRecognizer.requestAuthorization { status in
    authOK = (status == .authorized)
    sem.signal()
}
sem.wait()

guard authOK else {
    fputs("error: 语音识别未授权\n", stderr)
    fputs("请在系统设置 → 隐私与安全性 → 语音识别 中授权终端\n", stderr)
    exit(1)
}

// --- Load custom vocabulary ---
let vocabDir = ProcessInfo.processInfo.environment["CLAUDE_VOICE_DIR"]
    ?? "\(NSHomeDirectory())/.claude-voice-zh"
let vocabFile = "\(vocabDir)/vocab.txt"

var contextualStrings: [String] = [
    "Claude", "Claude Code", "Codex", "Cursor", "Copilot", "GitHub", "GitLab",
    "Vercel", "Docker", "Kubernetes", "Homebrew", "npm", "Vite", "Webpack",
    "TypeScript", "JavaScript", "Python", "Swift", "React", "Next.js", "Vue",
    "Node.js", "Tailwind", "Svelte",
    "commit", "push", "pull", "merge", "rebase", "branch", "checkout",
    "PR", "pull request", "code review", "review", "deploy", "release",
    "API", "SDK", "CLI", "function", "component", "module", "import", "export",
    "async", "await", "callback", "promise", "interface", "endpoint",
    "refactor", "debug", "build", "test", "lint",
    "LLM", "GPT", "token", "prompt", "model", "embedding", "fine-tune",
    "Anthropic", "OpenAI", "Gemini", "Whisper",
]

if let custom = try? String(contentsOfFile: vocabFile, encoding: .utf8) {
    let lines = custom.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    contextualStrings.append(contentsOf: lines)
}

// --- Audio engine ---
let audioEngine = AVAudioEngine()
let inputNode = audioEngine.inputNode
let inputFmt = inputNode.outputFormat(forBus: 0)

// Audio file writer: save in native format (afconvert handles 16kHz conversion later)
let cafURL = URL(fileURLWithPath: audioFile)
var audioWriter: AVAudioFile?
do {
    audioWriter = try AVAudioFile(
        forWriting: cafURL,
        settings: inputFmt.settings,
        commonFormat: inputFmt.commonFormat,
        interleaved: inputFmt.isInterleaved
    )
} catch {
    fputs("warning: cannot create audio file: \(error)\n", stderr)
}

// --- Recognition request ---
let request = SFSpeechAudioBufferRecognitionRequest()
request.shouldReportPartialResults = true
request.taskHint = .dictation
request.contextualStrings = contextualStrings

if #available(macOS 13.0, *) {
    request.addsPunctuation = true
}

// --- Install audio tap: feed Apple + save audio ---
inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { buf, _ in
    request.append(buf)
    try? audioWriter?.write(from: buf)
}

audioEngine.prepare()
do {
    try audioEngine.start()
} catch {
    fputs("error: audio engine failed: \(error)\n", stderr)
    exit(1)
}

// --- State ---
var currentText = ""
var isShuttingDown = false

func writeState(_ mode: String, _ text: String) {
    try? "\(mode)\n\(text)".write(toFile: stateFile, atomically: true, encoding: .utf8)
}

// --- Recognition task ---
let _ = speechRecognizer.recognitionTask(with: request) { result, error in
    guard !isShuttingDown else { return }

    if let result = result {
        currentText = result.bestTranscription.formattedString
        writeState("recording", currentText)
    }

    if let err = error as NSError?, err.code != 1 && err.code != 203 {
        fputs("recognition error (\(err.code)): \(err.localizedDescription)\n", stderr)
    }
}

// --- Graceful shutdown ---
func shutdown() {
    guard !isShuttingDown else { return }
    isShuttingDown = true

    request.endAudio()
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioWriter = nil  // flush and close audio file

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        try? text.write(toFile: resultFile, atomically: true, encoding: .utf8)
        exit(0)
    }
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)

let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSrc.setEventHandler { shutdown() }
termSrc.resume()

let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSrc.setEventHandler { shutdown() }
intSrc.resume()

RunLoop.current.run()
