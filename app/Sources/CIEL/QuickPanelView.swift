import SwiftUI
import AppKit

struct QuickPanelView: View {
    @EnvironmentObject var engine: Engine
    @Environment(\.openWindow) private var openWindow
    @State private var permsOK = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(engine.statusColor).frame(width: 10, height: 10)
                Text(engine.statusLine).font(.subheadline).lineLimit(2)
            }
            Text(engine.config.model)
                .font(.caption)
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
                .lineLimit(1)
            Toggle("Allow C.I.E.L to speak", isOn: speakBinding)
                .toggleStyle(.switch)
                .font(.caption)
            if let reply = engine.history.first(where: { $0.reply != nil })?.reply {
                Text("C.I.E.L — " + reply)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            Label(permsOK ? "Permissions OK" : "Permissions needed — open Command Center",
                  systemImage: permsOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(permsOK ? .green : .orange)
            HStack {
                Button("Open Command Center") {
                    openWindow(id: "commandCenter")
                    NSApp.activate(ignoringOtherApps: true)   // LSUIElement: window opens behind everything otherwise
                }
                Spacer()
                Button("Quit") { engine.stop(); NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            permsOK = Permissions.mic && Permissions.accessibility && Permissions.inputMonitoring
            engine.autoHealPermissions()
        }
    }

    private var speakBinding: Binding<Bool> {
        Binding(
            get: { engine.config.speak_mode ?? false },
            set: { newValue in
                engine.config.speak_mode = newValue
                engine.restart()
            }
        )
    }
}
