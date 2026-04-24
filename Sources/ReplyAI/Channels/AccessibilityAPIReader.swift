import Foundation
import AppKit
import ApplicationServices

// MARK: - Abstraction layer

/// One node in an accessibility element tree.
/// The protocol exists so tests can inject a mock tree without a live process.
protocol AXElement {
    var role: String? { get }
    var title: String? { get }
    var children: [any AXElement] { get }
}

/// Creates the root accessibility element for a given process.
/// The production conformance delegates to AXUIElementCreateApplication;
/// tests return a fully controlled MockAXElement tree.
protocol AXElementFactory {
    func rootElement(forPID pid: pid_t) -> (any AXElement)?
}

// MARK: - Production wrapper around real AXUIElement

struct RealAXElement: AXElement {
    let element: AXUIElement

    var role: String? { string(for: kAXRoleAttribute as CFString) }
    var title: String? { string(for: kAXTitleAttribute as CFString) }

    var children: [any AXElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let arr = ref as? [AXUIElement] else { return [] }
        return arr.map { RealAXElement(element: $0) }
    }

    private func string(for attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }
}

/// Default factory: wraps AXUIElementCreateApplication(pid).
struct DefaultAXElementFactory: AXElementFactory {
    func rootElement(forPID pid: pid_t) -> (any AXElement)? {
        RealAXElement(element: AXUIElementCreateApplication(pid))
    }
}

// MARK: - Reader

/// Reads the Messages.app conversation list via the Accessibility API.
///
/// Requires Accessibility permission (System Settings → Privacy → Accessibility).
/// Returns [] gracefully when not trusted or Messages.app is not running —
/// no permission dialogs are triggered.
///
/// All three seams (pid, factory, isTrusted) are injectable so the type is
/// fully unit-testable without a running process or a real AX grant.
final class AccessibilityAPIReader {

    /// Returns the PID for com.apple.MobileSMS, or nil if the process is not running.
    var pidProvider: () -> pid_t?

    /// Creates the root AX element for the target process.
    var elementFactory: any AXElementFactory

    /// Returns whether this process has Accessibility permission.
    /// We avoid calling AXUIElementCopyAttributeValue when not trusted
    /// because it would trigger a TCC dialog.
    var isTrustedProvider: () -> Bool

    init(
        pidProvider: @escaping () -> pid_t? = {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.MobileSMS")
                .first?.processIdentifier
        },
        elementFactory: any AXElementFactory = DefaultAXElementFactory(),
        isTrustedProvider: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.pidProvider      = pidProvider
        self.elementFactory   = elementFactory
        self.isTrustedProvider = isTrustedProvider
    }

    /// Returns display names for all conversations visible in the Messages sidebar.
    /// Returns [] if Accessibility is not trusted, Messages.app is not running,
    /// or no conversation rows are found in the element tree.
    func conversationNames() -> [String] {
        guard isTrustedProvider() else { return [] }
        guard let pid = pidProvider() else { return [] }
        guard let root = elementFactory.rootElement(forPID: pid) else { return [] }
        return collectNames(from: root)
    }

    // MARK: - Private

    /// Depth-first traversal: collects AXTitle from every AXRow descendant.
    /// Messages.app sidebar rows carry their conversation name in kAXTitleAttribute.
    private func collectNames(from element: any AXElement) -> [String] {
        var names: [String] = []
        if element.role == "AXRow", let title = element.title, !title.isEmpty {
            names.append(title)
        }
        for child in element.children {
            names.append(contentsOf: collectNames(from: child))
        }
        return names
    }
}
