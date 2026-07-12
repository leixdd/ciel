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
        case "loading", "transcribing": return .orange
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
    case overview, model, history, tools, debug, settings
    var id: Self { self }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: return "waveform"
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
            engine.autoHealPermissions()
        }
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
