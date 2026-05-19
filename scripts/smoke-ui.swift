#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Darwin
import Foundation

private let bundleID = "co.replyai.mac"
private let onboardingCompletedKey = "pref.app.onboardingCompleted"
private let useMLXKey = "pref.model.useMLX"
private let welcomeGateGetStartedID = "replyai.onboarding.welcome-gate.get-started"
private let permissionButtonIDs = [
    "replyai.onboarding.permissions.button.full-disk-access",
    "replyai.onboarding.permissions.button.contacts",
    "replyai.onboarding.permissions.button.notifications",
    "replyai.onboarding.permissions.button.accessibility",
]
private let openInboxID = "replyai.app.prototype.open-inbox"
private let threadRowPrefix = "replyai.inbox.thread-row."
private let composerEditorID = "replyai.inbox.composer.editor"
private let warmToneID = "replyai.inbox.tone-pill.warm"

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

private func setBoolDefault(_ key: String, _ value: Bool) {
    guard run(["/usr/bin/defaults", "write", bundleID, key, "-bool", value ? "true" : "false"]) == 0 else {
        fail("could not set \(key)=\(value)")
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
    matching predicate: (String) -> Bool,
    in element: AXUIElement,
    depth: Int = 0,
    visited: inout Int
) -> AXUIElement? {
    visited += 1
    guard visited <= 5_000, depth <= 24 else { return nil }

    if let identifier = stringAttribute(element, "AXIdentifier" as CFString),
       predicate(identifier) {
        return element
    }

    for child in elementArrayAttribute(element, kAXChildrenAttribute as CFString) {
        if let match = findElement(matching: predicate, in: child, depth: depth + 1, visited: &visited) {
            return match
        }
    }
    return nil
}

private func waitForElement(identifier: String, appElement: AXUIElement, timeout: TimeInterval) -> AXUIElement? {
    waitForElement(matching: { $0 == identifier }, appElement: appElement, timeout: timeout)
}

private func waitForElement(identifierPrefix: String, appElement: AXUIElement, timeout: TimeInterval) -> AXUIElement? {
    waitForElement(matching: { $0.hasPrefix(identifierPrefix) }, appElement: appElement, timeout: timeout)
}

private func waitForElement(
    matching predicate: @escaping (String) -> Bool,
    appElement: AXUIElement,
    timeout: TimeInterval
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        var visited = 0
        if let element = findElement(matching: predicate, in: appElement, visited: &visited) {
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

private func windowElement(title: String, appElement: AXUIElement) -> AXUIElement? {
    elementArrayAttribute(appElement, kAXWindowsAttribute as CFString).first {
        stringAttribute($0, kAXTitleAttribute as CFString) == title
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

private func waitForWindowElement(title: String, appElement: AXUIElement, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let window = windowElement(title: title, appElement: appElement) {
            return window
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
}

private func pressElementOrButtonAncestor(_ element: AXUIElement) -> AXError {
    let directPressError = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if directPressError == .success {
        return .success
    }

    var current = element
    var clickCandidates = [element]
    for _ in 0..<8 {
        guard let parent = elementAttribute(current, kAXParentAttribute as CFString) else {
            break
        }
        clickCandidates.append(parent)
        if stringAttribute(parent, kAXRoleAttribute as CFString) == (kAXButtonRole as String) {
            return AXUIElementPerformAction(parent, kAXPressAction as CFString)
        }
        current = parent
    }

    for candidate in clickCandidates {
        if clickElementCenter(candidate) {
            return .success
        }
    }
    return directPressError
}

private func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
    guard let value = copyAttribute(element, attribute) else { return nil }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

private func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
    guard let value = copyAttribute(element, attribute) else { return nil }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}

private func clickElementCenter(_ element: AXUIElement) -> Bool {
    guard let position = pointAttribute(element, kAXPositionAttribute as CFString),
          let size = sizeAttribute(element, kAXSizeAttribute as CFString) else {
        return false
    }

    let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.25)
    return true
}

private func pressReturnKey() {
    let returnKeyCode = CGKeyCode(36)
    CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: false)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.25)
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

private func printExposedIdentifiers(root: AXUIElement) {
    let exposed = exposedReplyAIIdentifiers(appElement: root).joined(separator: "\n  ")
    if !exposed.isEmpty {
        fputs("smoke-ui: exposed ReplyAI identifiers:\n  \(exposed)\n", stderr)
    }
}

guard AXIsProcessTrusted() else {
    fail("Accessibility permission is not granted to this shell")
}

setBoolDefault(onboardingCompletedKey, false)
setBoolDefault(useMLXKey, false)
terminateExistingApp()
let app = launchApp()
let appElement = AXUIElementCreateApplication(app.processIdentifier)

for permissionButtonID in permissionButtonIDs {
    guard waitForElement(identifier: permissionButtonID, appElement: appElement, timeout: 10) != nil else {
        printExposedIdentifiers(root: appElement)
        fail("permission button identifier did not appear: \(permissionButtonID)")
    }
}

guard let getStarted = waitForElement(identifier: welcomeGateGetStartedID, appElement: appElement, timeout: 10) else {
    printExposedIdentifiers(root: appElement)
    fail("welcome-gate get-started identifier did not appear")
}

let startPressError = pressElementOrButtonAncestor(getStarted)
if startPressError != .success {
    // SwiftUI exposes this control's identifier but not always an AXPress
    // action. The button has Return as its keyboard shortcut, so use that
    // as the fallback and let the next wait prove the transition happened.
    pressReturnKey()
}

guard let openInbox = waitForElement(identifier: openInboxID, appElement: appElement, timeout: 10) else {
    printExposedIdentifiers(root: appElement)
    fail("open-inbox button identifier did not appear")
}

let pressError = pressElementOrButtonAncestor(openInbox)
guard pressError == .success else {
    fail("AX press failed for open-inbox button: \(pressError.rawValue)")
}

guard waitForWindow(title: "Inbox", appElement: appElement, timeout: 5) else {
    fail("Inbox window did not appear after pressing open-inbox")
}

guard let inboxWindow = waitForWindowElement(title: "Inbox", appElement: appElement, timeout: 5) else {
    fail("Inbox window appeared in title list but AX element was unavailable")
}

guard let firstThreadRow = waitForElement(identifierPrefix: threadRowPrefix, appElement: inboxWindow, timeout: 8) else {
    fail("no thread row identifier appeared in Inbox window")
}

let firstThreadID = stringAttribute(firstThreadRow, "AXIdentifier" as CFString) ?? "\(threadRowPrefix)<unknown>"
let threadPressError = pressElementOrButtonAncestor(firstThreadRow)
guard threadPressError == .success else {
    fail("AX press failed for first thread row \(firstThreadID): \(threadPressError.rawValue)")
}

guard waitForElement(identifier: composerEditorID, appElement: inboxWindow, timeout: 8) != nil else {
    printExposedIdentifiers(root: inboxWindow)
    fail("composer editor identifier did not appear after selecting \(firstThreadID)")
}

guard waitForElement(identifier: warmToneID, appElement: inboxWindow, timeout: 8) != nil else {
    fail("warm tone-pill identifier did not appear after selecting \(firstThreadID)")
}

let titles = windowTitles(appElement: appElement).joined(separator: ", ")
print("smoke-ui: PASS - onboarding, open-inbox click, thread selection, composer, and warm tone verified [\(titles)]")
