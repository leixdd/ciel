import Foundation

// ponytail: personal-machine tool, hardcoded root
struct Config: Codable, Equatable {
    var model: String
    var hotkey: String
    var log_dir: String
    var input_device: String?
    var output_device: String?
    var speak_mode: Bool?
    var tts_model: String?
    var tts_voice: String?

    static let root = "/Users/leilei/OTis/ciel-ai-workspace/CIELAI"
    static let path = root + "/config.json"
    static let `default` = Config(
        model: "mlx-community/whisper-large-v3-mlx-8bit",
        hotkey: "alt_r",
        log_dir: root + "/brain/memory/logs",
        input_device: nil,
        output_device: nil,
        speak_mode: nil,
        tts_model: nil,
        tts_voice: nil
    )
}

struct Entry: Identifiable {
    let id = UUID()
    let ts: String
    let text: String
    var reply: String? = nil
}

struct LogLine: Identifiable {
    let id = UUID()
    let ts: Date
    let text: String
}

private func splitLines(_ buffer: inout Data) -> [String] {
    var out: [String] = []
    while let i = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
        let line = buffer.subdata(in: buffer.startIndex..<i)
        buffer.removeSubrange(buffer.startIndex...i)
        if let s = String(data: line, encoding: .utf8), !s.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(s)
        }
    }
    return out
}

struct ToolInfo: Decodable, Identifiable {
    var name: String
    var description: String
    var permission: String?
    var id: String { name }
}

// One line of engine stdout / history.jsonl.
private struct EngineEvent: Decodable {
    var event: String?
    var ts: String?
    var model: String?
    var hotkey: String?
    var text: String?
    var reply: String?
    var message: String?
    var devices: [String]?
    var output_devices: [String]?
    var tools: [ToolInfo]?
}

@MainActor
final class Engine: ObservableObject {
    @Published var status: String = "loading"
    @Published var statusDetail: String = ""
    @Published var history: [Entry] = []
    @Published var config: Config
    @Published private(set) var startedWithPerms = false
    @Published private(set) var debugLog: [LogLine] = []
    @Published var inputDevices: [String] = []
    @Published var outputDevices: [String] = []
    @Published var toolsList: [ToolInfo] = []

    private var process: Process?
    private var stdin: FileHandle?
    private var restarting = false
    private var logFile: FileHandle?
    private static let logCap = 500

    func clearLog() { debugLog = [] }

    private func appendLog(_ lines: [String]) {
        let now = Date()
        debugLog.append(contentsOf: lines.map { LogLine(ts: now, text: $0) })
        if debugLog.count > Self.logCap { debugLog.removeFirst(debugLog.count - Self.logCap) }
        if let fh = logFile, let data = lines.map({ $0 + "\n" }).joined().data(using: .utf8) {
            try? fh.write(contentsOf: data)
        }
    }

    init() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Config.path)),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            config = cfg
        } else {
            config = .default
        }
        start()
    }

    func start() {
        startedWithPerms = Permissions.engineReadyPerms
        restarting = false
        writeConfig()
        loadHistory()

        FileManager.default.createFile(atPath: config.log_dir + "/engine.log", contents: nil)
        logFile = FileHandle(forWritingAtPath: config.log_dir + "/engine.log")
        appendLog(["[app] spawning engine (model \(config.model))"])

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "uv", "run", Config.root + "/brain/main.py",
            "--config", Config.path,
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        proc.environment = env

        let inPipe = Pipe()
        proc.standardInput = inPipe
        stdin = inPipe.fileHandleForWriting

        let pipe = Pipe()
        proc.standardOutput = pipe

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            let lines = splitLines(&buffer)
            guard !lines.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                self.appendLog(lines)
                for line in lines {
                    if let ev = try? JSONDecoder().decode(EngineEvent.self, from: Data(line.utf8)) {
                        self.handle(ev)
                    }
                }
            }
        }

        let errPipe = Pipe()
        proc.standardError = errPipe
        var errBuf = Data()
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errBuf.append(chunk)
            let lines = splitLines(&errBuf)
            guard !lines.isEmpty else { return }
            Task { @MainActor in self?.appendLog(lines) }
        }

        proc.terminationHandler = { p in
            Task { @MainActor in
                if !self.restarting {
                    self.status = "exited"
                    self.statusDetail = "engine exited"
                    self.appendLog(["[app] engine terminated (status \(p.terminationStatus))"])
                }
            }
        }

        do {
            try proc.run()
            process = proc
            status = "loading"
            statusDetail = ""
        } catch {
            status = "error"
            statusDetail = error.localizedDescription
            appendLog(["[app] failed to launch: \(error.localizedDescription)"])
        }
    }

    private func handle(_ ev: EngineEvent) {
        if let devices = ev.devices { inputDevices = devices }
        if let d = ev.output_devices { outputDevices = d }
        if let tools = ev.tools { toolsList = tools }
        switch ev.event {
        case "loading": status = "loading"; statusDetail = ""
        case "ready": status = "ready"; statusDetail = ""
        case "recording": status = "recording"; statusDetail = ""
        case "transcribing": status = "transcribing"; statusDetail = ""
        case "speaking": status = "speaking"; statusDetail = ""
        case "idle": status = "ready"; statusDetail = ""
        case "transcript":
            if let text = ev.text {
                // Typed chat pre-inserts a reply-less entry; fill it. Dictation has none — insert.
                if let idx = history.lastIndex(where: { $0.reply == nil && $0.text == text }) {
                    history[idx].reply = ev.reply
                } else {
                    history.insert(Entry(ts: ev.ts ?? "", text: text, reply: ev.reply), at: 0)
                }
            }
            status = "ready"; statusDetail = ""
        case "error":
            status = "error"
            statusDetail = ev.message ?? "error"
        default:
            break
        }
    }

    func restart() {
        appendLog(["[app] restarting engine"])
        writeConfig()
        loadHistory()
        guard let proc = process, proc.isRunning else { start(); return }
        restarting = true
        (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (proc.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        proc.terminationHandler = { _ in
            Task { @MainActor in self.start() }
        }
        proc.terminate()
    }

    func stop() {
        restarting = true
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func send(_ text: String) {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["chat": msg]),
              let line = String(data: data, encoding: .utf8) else { return }
        try? stdin?.write(contentsOf: Data((line + "\n").utf8))
        history.insert(Entry(ts: "", text: msg, reply: nil), at: 0)  // optimistic; reply filled by transcript event
    }

    func speak(_ text: String, lang: String, voice: String, model: String) {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["tts": ["text": msg, "lang": lang, "voice": voice, "model": model]]),
              let line = String(data: data, encoding: .utf8) else { return }
        try? stdin?.write(contentsOf: Data((line + "\n").utf8))
    }

    func autoHealPermissions() {
        // Auto-heal: a pynput listener created before the grants is permanently dead.
        if Permissions.engineReadyPerms && !startedWithPerms { restart() }
    }

    private func writeConfig() {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(config) {
            try? data.write(to: URL(fileURLWithPath: Config.path))
        }
    }

    private func loadHistory() {
        let url = URL(fileURLWithPath: config.log_dir + "/history.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            history = []
            return
        }
        var entries: [Entry] = []
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let ev = try? JSONDecoder().decode(EngineEvent.self, from: data),
                  ev.event == "transcript", let text = ev.text else { continue }
            entries.append(Entry(ts: ev.ts ?? "", text: text, reply: ev.reply))
        }
        history = Array(entries.suffix(200).reversed())
    }
}
