import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var engine: Engine?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Permissions.requestAll()
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.engine?.stop()
    }
}

@main
struct CIELApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = Engine()

    var body: some Scene {
        MenuBarExtra {
            QuickPanelView()
                .environmentObject(engine)
        } label: {
            Image(systemName: menuBarSymbol)
                .onAppear { AppDelegate.engine = engine }
        }
        .menuBarExtraStyle(.window)

        Window("C.I.E.L", id: "commandCenter") {
            CommandCenterView()
                .environmentObject(engine)
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 760, height: 520)
    }

    private var menuBarSymbol: String {
        switch engine.status {
        case "recording": return "waveform.circle.fill"
        case "loading": return "waveform.slash"
        default: return "waveform"
        }
    }
}
