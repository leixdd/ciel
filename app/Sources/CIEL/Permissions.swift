import AVFoundation
import ApplicationServices
import EventKit
import IOKit.hid
import AppKit

enum Permissions {
    // Order matters: IOHID before AX (rdar://7381305 — an earlier AX check can
    // suppress the Input Monitoring prompt).
    static func requestAll() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)          // Input Monitoring
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)                       // Accessibility
        AVCaptureDevice.requestAccess(for: .audio) { _ in }           // Microphone
    }

    static var mic: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    static var engineReadyPerms: Bool { inputMonitoring && accessibility }
    static var calendar: Bool { EKEventStore.authorizationStatus(for: .event).rawValue == 3 }  // .fullAccess; rawValue dodges the macOS-14-only enum case on the macOS 13 target

    static func requestCalendar(_ done: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in DispatchQueue.main.async { done(granted) } }
        } else {
            store.requestAccess(to: .event) { granted, _ in DispatchQueue.main.async { done(granted) } }
        }
    }

    static func openSettings(_ anchor: String) {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)!)
    }
}
