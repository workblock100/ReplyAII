#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Darwin
import Foundation

private let bundleID = "co.replyai.mac"
private let onboardingCompletedKey = "pref.app.onboardingCompleted"
private let useMLXKey = "pref.model.useMLX"
private let openInboxID = "replyai.app.prototype.open-inbox"

private let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let defaultAppPath = repo.appendingPathComponent("build/ReplyAI.app").path
private let appPath = CommandLine.arguments.dropFirst().first ?? defaultAppPath

@discardableResult
private func run(_ args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0])
    process.arguments = Array(args.dropFirst())
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 127
    }
}

private func fail(_ message: String) -> Never {
    fputs("smoke-ui: \(message)\n", stderr)
    exit(1)
}

private func setLaunchDefaults() {
    guard run(["/usr/bin/defaults", "write", bundleID, onboardingCompletedKey, "-bool", "true"]) == 0 else {
        fail("could not set onboarding completed default")
    }
    guard run(["/usr/bin/defaults", "write", bundleID, useMLXKey, "-bool", "false"]) == 0 else {
        fail("could not disable MLX default")
    }
}

private func terminateExistingApp() {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        app.terminate()
    }
    Thread.sleep(forTimeInterval: 1.5)
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
        app.forceTerminate()
    }
}

private func launchApp() -> NSRunningApplication {
    let url = URL(fileURLWithPath: appPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        fail("app bundle does not exist at \(url.path); run ./scripts/build.sh debug first")
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    var launchedApp: NSRunningApplication?
    var launchError: Error?
    let semaphore = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        launchedApp = app
        launchError = error
        semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + 10) == .success else {
        fail("timed out launching ReplyAI")
    }
    if let launchError {
        fail("launch failed: \(launchError.localizedDescription)")
    }
    guard let launchedApp else {
        fail("launch returned no NSRunningApplication")
    }
    return launchedApp
}

private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> Any? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success else { return nil }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    copyAttribute(element, attribute) as? String
}

private func elementArrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
    copyAttribute(element, attribute) as? [AXUIElement] ?? []
}

private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
    guard let value = copyAttribute(element, attribute) else { return nil }
    return (value as! AXUIElement)
}

private func findElement(
    identifier: String,
    in element: AXUIElement,
    depth: Int = 0,
    visited: inout Int
) -> AXUIElement? {
    visited += 1
    guard visited <= 5_000, depth <= 24 else { return nil }

    if stringAttribute(element, "AXIdentifier" as CFString) == identifier {
        return element
    }

    for child in elementArrayAttribute(element, kAXChildrenAttribute as CFString) {
        if let match = findElement(identifier: identifier, in: child, depth: depth + 1, visited: &visited) {
            return match
        }
    }
    return nil
}

private func waitForElement(identifier: String, appElement: AXUIElement, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        var visited = 0
        if let element = findElement(identifier: identifier, in: appElement, visited: &visited) {
            return element
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
}

private func windowTitles(appElement: AXUIElement) -> [String] {
    elementArrayAttribute(appElement, kAXWindowsAttribute as CFString).compactMap {
        stringAttribute($0, kAXTitleAttribute as CFString)
    }
}

private func waitForWindow(title: String, appElement: AXUIElement, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if windowTitles(appElement: appElement).contains(title) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
}

private func pressElementOrButtonAncestor(_ element: AXUIElement) -> AXError {
    let directPressError = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if directPressError == .success {
        return .success
    }

    var current = element
    for _ in 0..<8 {
        guard let parent = elementAttribute(current, kAXParentAttribute as CFString) else {
            return directPressError
        }
        if stringAttribute(parent, kAXRoleAttribute as CFString) == kAXButtonRole {
            return AXUIElementPerformAction(parent, kAXPressAction as CFString)
        }
        current = parent
    }
    return directPressError
}

private func collectReplyAIIdentifiers(in element: AXUIElement, depth: Int = 0, visited: inout Int, into output: inout [String]) {
    visited += 1
    guard visited <= 5_000, depth <= 24 else { return }

    if let identifier = stringAttribute(element, "AXIdentifier" as CFString),
       identifier.hasPrefix("replyai.") {
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? "unknown-role"
        let title = stringAttribute(element, kAXTitleAttribute as CFString) ?? ""
        output.append("\(identifier) [\(role)] \(title)")
    }

    for child in elementArrayAttribute(element, kAXChildrenAttribute as CFString) {
        collectReplyAIIdentifiers(in: child, depth: depth + 1, visited: &visited, into: &output)
    }
}

private func exposedReplyAIIdentifiers(appElement: AXUIElement) -> [String] {
    var visited = 0
    var output: [String] = []
    collectReplyAIIdentifiers(in: appElement, visited: &visited, into: &output)
    return output.sorted()
}

guard AXIsProcessTrusted() else {
    fail("Accessibility permission is not granted to this shell")
}

setLaunchDefaults()
terminateExistingApp()
let app = launchApp()
let appElement = AXUIElementCreateApplication(app.processIdentifier)

guard let openInbox = waitForElement(identifier: openInboxID, appElement: appElement, timeout: 10) else {
    let exposed = exposedReplyAIIdentifiers(appElement: appElement).joined(separator: "\n  ")
    if !exposed.isEmpty {
        fputs("smoke-ui: exposed ReplyAI identifiers:\n  \(exposed)\n", stderr)
    }
    fail("open-inbox button identifier did not appear")
}

let pressError = pressElementOrButtonAncestor(openInbox)
guard pressError == .success else {
    fail("AX press failed for open-inbox button: \(pressError.rawValue)")
}

guard waitForWindow(title: "Inbox", appElement: appElement, timeout: 5) else {
    fail("Inbox window did not appear after pressing open-inbox")
}

let titles = windowTitles(appElement: appElement).joined(separator: ", ")
print("smoke-ui: PASS - open-inbox AX press opened Inbox window [\(titles)]")
