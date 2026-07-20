import SwiftUI
import AppKit

let models = [
    "mlx-community/whisper-large-v3-turbo",
    "mlx-community/whisper-large-v3-mlx-8bit",
    "mlx-community/whisper-large-v3-mlx-4bit",
    "mlx-community/whisper-large-v3-mlx",
    "mlx-community/distil-whisper-large-v3",
]

let ttsModels = [
    "mlx-community/Kokoro-82M-bf16",
    "mlx-community/Kokoro-82M-8bit",
    "mlx-community/Kokoro-82M-6bit",
    "mlx-community/Kokoro-82M-4bit",
    "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-6bit",  // suited to 16GB M2 Pro: quantized, ~2.7GB
    "novita/fish-audio-s2-pro",  // cloud (Novita) — needs a Novita API key in Settings
]

// Novita Fish Audio S2 Pro voices. `id` is the reference_id; personality is descriptive; temp/speed/
// volume are the voice's default tuning preset (editable per-session in the TTS page).
struct FishVoice: Identifiable {
    let label: String, id: String, personality: String
    let temperature: Double, speed: Double, volume: Double
}
let fishVoices: [FishVoice] = [
    FishVoice(label: "yuki", id: "ef6cb429e08b4b669537484c56f4bd07",
              personality: "Bright, energetic voice with a lively, upbeat delivery.",
              temperature: 0.7, speed: 1.0, volume: 0),
    FishVoice(label: "3d3n", id: "9bb57c9442c4489a98945ba19e055638",
              personality: "Calm, measured voice with a warm, grounded tone.",
              temperature: 0.6, speed: 1.0, volume: 0),
    FishVoice(label: "leiden", id: "5161d41404314212af1254556477c17d",
              personality: "A youthful and friendly female voice with a gentle, polite tone. Her speech is clear and expressive, making it well-suited for conversational and narrative content.",
              temperature: 0.7, speed: 1.0, volume: 0),
]
let fishVoicesByID = Dictionary(uniqueKeysWithValues: fishVoices.map { ($0.id, $0) })

// Qwen3-TTS is a different engine: named speakers (multilingual) + language names, auto-detect available.
let qwenSpeakers = ["serena", "vivian", "uncle_fu", "ryan", "aiden", "ono_anna", "sohee", "eric", "dylan"]
let qwenLanguages: [(label: String, value: String)] = [
    ("Auto-detect", "auto"), ("English", "english"), ("Chinese", "chinese"), ("Japanese", "japanese"),
    ("Korean", "korean"), ("Spanish", "spanish"), ("French", "french"), ("German", "german"),
    ("Italian", "italian"), ("Portuguese", "portuguese"), ("Russian", "russian"),
]

let ttsVoices: [(label: String, value: String)] = [
    ("Heart (US female — best)", "af_heart"),
    ("Bella (US female)", "af_bella"),
    ("Nicole (US female)", "af_nicole"),
    ("Sarah (US female)", "af_sarah"),
    ("Fenrir (US male)", "am_fenrir"),
    ("Michael (US male)", "am_michael"),
    ("Puck (US male)", "am_puck"),
    ("Emma (UK female)", "bf_emma"),
    ("Isabella (UK female)", "bf_isabella"),
    ("Fable (UK male)", "bm_fable"),
    ("George (UK male)", "bm_george"),
]

// Kokoro languages whose g2p backend ships in this install (code = Kokoro lang_code).
// ponytail: add ("Mandarin Chinese","z") after `uv add misaki[zh]` (needs jieba/pypinyin backend).
let ttsLanguages: [(label: String, value: String)] = [
    ("American English", "a"),
    ("British English", "b"),
    ("Spanish", "e"),
    ("French", "f"),
    ("Hindi", "h"),
    ("Italian", "i"),
    ("Portuguese (Brazil)", "p"),
    ("Japanese", "j"),
]

// Kokoro voices per language code (from the model's voices manifest). Filters the voice picker.
let ttsVoicesByLang: [String: [String]] = [
    "a": ["af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore", "af_nicole",
          "af_nova", "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir",
          "am_liam", "am_michael", "am_onyx", "am_puck", "am_santa"],
    "b": ["bf_emma", "bf_alice", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis"],
    "e": ["ef_dora", "em_alex", "em_santa"],
    "f": ["ff_siwis"],
    "h": ["hf_alpha", "hf_beta", "hm_omega", "hm_psi"],
    "i": ["if_sara", "im_nicola"],
    "p": ["pf_dora", "pm_alex", "pm_santa"],
    "j": ["jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo"],
]

let hotkeys: [(label: String, value: String)] = [
    ("Right Option ⌥", "alt_r"),
    ("Left Option ⌥", "alt_l"),
    ("Right Command ⌘", "cmd_r"),
    ("Right Control ⌃", "ctrl_r"),
    ("F13", "f13"),
    ("F14", "f14"),
    ("F15", "f15"),
]

// MARK: Status

extension Engine {
    var statusColor: Color {
        switch status {
        case "ready": return .green
        case "recording": return .red
        case "loading", "transcribing", "processing": return .orange
        case "speaking": return .blue
        case "error": return .red
        default: return .gray
        }
    }

    var statusLine: String {
        switch status {
        case "ready":
            let name = hotkeys.first { $0.value == config.hotkey }?.label ?? config.hotkey
            return "Ready — hold \(name)"
        case "recording": return "Recording…"
        case "transcribing": return "Transcribing…"
        case "processing": return "Processing…"
        case "speaking": return "Speaking…"
        case "loading": return "Loading model…"
        case "error": return statusDetail
        case "exited": return statusDetail.isEmpty ? "engine exited" : statusDetail
        default: return statusDetail
        }
    }
}

// MARK: Navigation

enum Page: String, CaseIterable, Identifiable {
    case overview, chat, tts, model, history, tools, debug, settings
    var id: Self { self }
    var label: String { self == .tts ? "TTS" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: return "waveform"
        case .chat: return "bubble.left.and.bubble.right"
        case .tts: return "speaker.wave.2"
        case .model: return "cpu"
        case .history: return "clock"
        case .tools: return "wrench.and.screwdriver"
        case .debug: return "terminal"
        case .settings: return "gearshape"
        }
    }
}

struct CommandCenterView: View {
    @EnvironmentObject var engine: Engine
    @State private var page: Page? = .overview

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label(page.label, systemImage: page.symbol)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch page ?? .overview {
            case .overview: OverviewPage()
            case .chat: ChatPage()
            case .tts: TtsPage()
            case .model: ModelPage()
            case .history: HistoryPage()
            case .tools: ToolsPage()
            case .debug: DebugPage()
            case .settings: SettingsPage()
            }
        }
    }
}

// MARK: Overview

private struct OverviewPage: View {
    @EnvironmentObject var engine: Engine
    @State private var perms = (mic: false, ax: false, input: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(engine.statusColor).frame(width: 14, height: 14)
                Text(engine.statusLine).font(.title2)
            }
            HStack {
                Text("Model").foregroundStyle(.secondary)
                Spacer()
                Text(engine.config.model).font(.callout)
            }
            HStack {
                Text("Hotkey").foregroundStyle(.secondary)
                Spacer()
                Text(hotkeys.first { $0.value == engine.config.hotkey }?.label ?? engine.config.hotkey)
                    .font(.callout)
            }
            if perms.mic && perms.ax && perms.input {
                Label("All permissions granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                permRow("Microphone", perms.mic, "Privacy_Microphone")
                permRow("Input Monitoring", perms.input, "Privacy_ListenEvent")
                permRow("Accessibility", perms.ax, "Privacy_Accessibility")
            }
            Button("Restart Engine") { engine.restart() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            perms = (Permissions.mic, Permissions.accessibility, Permissions.inputMonitoring)
            engine.autoHealPermissions()
        }
    }
}

// MARK: Model

private struct ModelPage: View {
    @EnvironmentObject var engine: Engine
    @State private var modelDraft = ""
    @State private var ttsModelDraft = ""

    private var ttsModel: String { engine.config.tts_model ?? "mlx-community/Kokoro-82M-bf16" }
    private var ttsVoice: String { engine.config.tts_voice ?? "af_heart" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODEL").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: modelPickerBinding) {
                ForEach(models, id: \.self) { Text($0).tag($0) }
                if !models.contains(engine.config.model) {
                    Text("Custom").tag("__custom__")
                }
            }
            .labelsHidden()
            TextField("Model override", text: $modelDraft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit {
                    guard modelDraft != engine.config.model else { return }
                    engine.config.model = modelDraft
                    engine.restart()
                }
                .onAppear { modelDraft = engine.config.model }
                .onChange(of: engine.config.model) { modelDraft = $0 }

            Text("SPEECH (TTS)").font(.caption).foregroundStyle(.secondary)
                .padding(.top, 14)
            Picker("", selection: ttsModelPickerBinding) {
                ForEach(ttsModels, id: \.self) { Text($0).tag($0) }
                if !ttsModels.contains(ttsModel) {
                    Text("Custom").tag("__custom__")
                }
            }
            .labelsHidden()
            TextField("TTS model override", text: $ttsModelDraft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit {
                    guard ttsModelDraft != ttsModel else { return }
                    engine.config.tts_model = ttsModelDraft
                    engine.restart()
                }
                .onAppear { ttsModelDraft = ttsModel }
                .onChange(of: engine.config.tts_model) { _ in ttsModelDraft = ttsModel }
            Picker("Voice", selection: ttsVoiceBinding) {
                ForEach(ttsVoices, id: \.value) { Text($0.label).tag($0.value) }
                if !ttsVoices.contains(where: { $0.value == ttsVoice }) {
                    Text("\(ttsVoice) (unavailable)").tag(ttsVoice)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 480, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelPickerBinding: Binding<String> {
        Binding(
            get: { models.contains(engine.config.model) ? engine.config.model : "__custom__" },
            set: { newValue in
                guard newValue != "__custom__", newValue != engine.config.model else { return }
                engine.config.model = newValue
                engine.restart()
            }
        )
    }

    private var ttsModelPickerBinding: Binding<String> {
        Binding(
            get: { ttsModels.contains(ttsModel) ? ttsModel : "__custom__" },
            set: { newValue in
                guard newValue != "__custom__", newValue != ttsModel else { return }
                engine.config.tts_model = newValue
                engine.restart()
            }
        )
    }

    private var ttsVoiceBinding: Binding<String> {
        Binding(
            get: { ttsVoice },
            set: { newValue in
                guard newValue != ttsVoice else { return }
                engine.config.tts_voice = newValue
                engine.restart()
            }
        )
    }
}

// MARK: History

// MARK: Chat

private struct ChatPage: View {
    @EnvironmentObject var engine: Engine
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(engine.history.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(entry.reply ?? "…").font(.callout)
                            .foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowSeparator(.hidden)
                    .id(entry.id)
                }
                .listStyle(.inset)
                .onChange(of: engine.history.count) { _ in
                    if let newest = engine.history.first { proxy.scrollTo(newest.id) }
                }
            }
            HStack(spacing: 8) {
                TextField("Message C.I.E.L…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }

    private func send() {
        engine.send(draft)
        draft = ""
    }
}

// MARK: TTS playground

private struct TtsPage: View {
    @EnvironmentObject var engine: Engine

    private var isFish: Bool { engine.ttsModel.hasPrefix("novita/") }
    private var isQwen: Bool { engine.ttsModel.contains("Qwen3-TTS") }
    private var langs: [(label: String, value: String)] { isQwen ? qwenLanguages : ttsLanguages }
    private var voices: [String] {
        if isFish { return fishVoices.map(\.id) }
        return isQwen ? qwenSpeakers : (ttsVoicesByLang[engine.ttsLang] ?? [])
    }
    private var selectedFish: FishVoice? { fishVoicesByID[engine.ttsVoice] }
    private var busy: Bool { engine.status == "processing" || engine.status == "speaking" }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEXT TO SPEECH").font(.caption).foregroundStyle(.secondary)
            Picker("Model", selection: $engine.ttsModel) {
                ForEach(ttsModels, id: \.self) { Text($0).tag($0) }
            }
            if isFish {
                Picker("Voice", selection: $engine.ttsVoice) {
                    ForEach(fishVoices) { Text($0.label).tag($0.id) }
                }
                if let fv = selectedFish {
                    Text(fv.personality).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    tuningRow("Temperature", $engine.ttsTemp, 0...1, "%.2f")
                    tuningRow("Speed", $engine.ttsSpeed, 0.5...2.0, "%.2f")
                    tuningRow("Volume", $engine.ttsVolume, -10...10, "%.0f")
                    HStack {
                        Spacer()
                        Button("Reset preset") { loadFishPreset() }.font(.caption)
                    }
                }
                Text("Cloud voice (Novita). Set the API key in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Language", selection: $engine.ttsLang) {
                    ForEach(langs, id: \.value) { Text($0.label).tag($0.value) }
                }
                Picker(isQwen ? "Speaker" : "Voice", selection: $engine.ttsVoice) {
                    ForEach(voices, id: \.self) { Text($0).tag($0) }
                }
            }
            TextEditor(text: $engine.ttsText)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
            HStack {
                if engine.status == "processing" { Text("Processing…").foregroundStyle(.secondary) }
                else if engine.status == "speaking" { Text("Speaking…").foregroundStyle(.secondary) }
                Spacer()
                if busy {
                    Button(role: .destructive) { engine.stopSpeaking() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
                Button {
                    engine.speak(engine.ttsText, lang: engine.ttsLang, voice: engine.ttsVoice, model: engine.ttsModel,
                                 temperature: engine.ttsTemp, speed: engine.ttsSpeed, volume: engine.ttsVolume)
                } label: {
                    Label("Speak", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(engine.ttsText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !engine.audioHistory.isEmpty {
                Divider()
                Text("RECENT CLIPS").font(.caption).foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(engine.audioHistory) { clip in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.text).font(.callout).lineLimit(2)
                                Text(clipCaption(clip)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { engine.replay(clip.file) } label: {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(busy)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .onChange(of: engine.ttsModel) { _ in engine.ttsLang = langs.first?.value ?? "a"; engine.ttsVoice = voices.first ?? "" }
      .onChange(of: engine.ttsLang) { _ in engine.ttsVoice = voices.first ?? "" }
      .onChange(of: engine.ttsVoice) { _ in if isFish { loadFishPreset() } }  // pick voice -> load its personality preset
    }

    @ViewBuilder
    private func tuningRow(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading).font(.caption)
            Slider(value: value, in: range)
            Text(String(format: fmt, value.wrappedValue)).font(.caption).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func loadFishPreset() {
        guard let fv = selectedFish else { return }
        engine.ttsTemp = fv.temperature; engine.ttsSpeed = fv.speed; engine.ttsVolume = fv.volume
    }

    private func clipCaption(_ c: AudioClip) -> String {
        let m = c.model.components(separatedBy: "/").last ?? c.model
        return [c.ts, m, c.voice].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

private struct HistoryPage: View {
    @EnvironmentObject var engine: Engine
    @State private var query = ""

    private var filtered: [Entry] {
        query.isEmpty ? engine.history : engine.history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 12)
            List(filtered) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.ts).font(.caption2).foregroundStyle(.secondary)
                    Text(entry.text).font(.callout).textSelection(.enabled)
                    if let reply = entry.reply {
                        Text("C.I.E.L — " + reply).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: Tools

private struct ToolsPage: View {
    @EnvironmentObject var engine: Engine
    @State private var permRefresh = false

    var body: some View {
        Group {
            if engine.toolsList.isEmpty {
                Text("No tools reported yet — engine still starting.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(engine.toolsList) { tool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.name).font(.headline)
                        Text(tool.description).font(.callout).foregroundStyle(.secondary)
                        permissionLine(tool.permission)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .id(permRefresh)
            }
        }
        .onAppear { engine.autoHealPermissions() }
    }

    @ViewBuilder
    private func permissionLine(_ permission: String?) -> some View {
        switch permission {
        case nil:
            Label("No permission needed", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case "calendars":
            permRow("Calendar access", Permissions.calendar, "Privacy_Calendars")
            if !Permissions.calendar {
                Button("Request Access…") {
                    Permissions.requestCalendar { _ in permRefresh.toggle() }
                }
                .font(.caption)
            }
        case let p?:
            Label("Needs: \(p)", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Debug

private struct DebugPage: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ENGINE LOG").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        engine.debugLog.map(\.text).joined(separator: "\n"), forType: .string)
                }
                Button("Clear") { engine.clearLog() }
            }
            .padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(engine.debugLog) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: engine.debugLog.count) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

// MARK: Settings

private struct SettingsPage: View {
    @EnvironmentObject var engine: Engine
    @State private var perms = (mic: false, ax: false, input: false)
    @State private var novitaKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS").font(.caption).foregroundStyle(.secondary)
                Picker("Hotkey", selection: hotkeyBinding) {
                    ForEach(hotkeys, id: \.value) { Text($0.label).tag($0.value) }
                }
                Picker("Microphone", selection: micBinding) {
                    Text("System default").tag("")
                    ForEach(engine.inputDevices, id: \.self) { Text($0).tag($0) }
                    if let cur = engine.config.input_device, !cur.isEmpty, !engine.inputDevices.contains(cur) {
                        Text("\(cur) (unavailable)").tag(cur)
                    }
                }
                Picker("Speaker", selection: speakerBinding) {
                    Text("System default").tag("")
                    ForEach(engine.outputDevices, id: \.self) { Text($0).tag($0) }
                    if let cur = engine.config.output_device, !cur.isEmpty, !engine.outputDevices.contains(cur) {
                        Text("\(cur) (unavailable)").tag(cur)
                    }
                }
                HStack {
                    Text("Log folder")
                    Spacer()
                    Text(engine.config.log_dir)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("Choose…") { chooseLogDir() }
                }
                HStack {
                    Text("Novita API key")
                    SecureField("for Fish Audio S2 Pro TTS", text: $novitaKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveNovitaKey() }
                    Button("Save") { saveNovitaKey() }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PERMISSIONS").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Engine") { engine.restart() }.font(.caption)
                }
                permRow("Microphone", perms.mic, "Privacy_Microphone")
                permRow("Input Monitoring", perms.input, "Privacy_ListenEvent")
                permRow("Accessibility", perms.ax, "Privacy_Accessibility")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            perms = (Permissions.mic, Permissions.accessibility, Permissions.inputMonitoring)
            novitaKeyDraft = engine.config.novita_api_key ?? ""
            engine.autoHealPermissions()
        }
    }

    private func saveNovitaKey() {
        let v = novitaKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        engine.config.novita_api_key = v.isEmpty ? nil : v
        engine.saveConfig()  // Python reads the key fresh from config.json; no restart needed
    }

    private var hotkeyBinding: Binding<String> {
        Binding(
            get: { engine.config.hotkey },
            set: { newValue in
                guard newValue != engine.config.hotkey else { return }
                engine.config.hotkey = newValue
                engine.restart()
            }
        )
    }

    private var micBinding: Binding<String> {
        Binding(
            get: { engine.config.input_device ?? "" },
            set: { newValue in
                guard newValue != (engine.config.input_device ?? "") else { return }
                engine.config.input_device = newValue.isEmpty ? nil : newValue
                engine.restart()
            }
        )
    }

    private var speakerBinding: Binding<String> {
        Binding(
            get: { engine.config.output_device ?? "" },
            set: { newValue in
                guard newValue != (engine.config.output_device ?? "") else { return }
                engine.config.output_device = newValue.isEmpty ? nil : newValue
                engine.restart()
            }
        )
    }

    private func chooseLogDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            engine.config.log_dir = url.path
            engine.restart()
        }
    }
}

// MARK: Shared

private func permRow(_ name: String, _ ok: Bool, _ anchor: String) -> some View {
    HStack {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(ok ? .green : .red)
        Text(name).font(.callout)
        Spacer()
        if !ok { Button("Open Settings…") { Permissions.openSettings(anchor) } }
    }
}
