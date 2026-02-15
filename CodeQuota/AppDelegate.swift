import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let iconView = UsageIconView()
            let hostingView = ClickThroughHostingView(rootView: iconView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            ])
            button.action = #selector(togglePanel)
            button.target = self
        }
        
        // Borderless panel — no titlebar, no arrow, tight to content
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        
        let contentView = ContentView()
            .environment(\.colorScheme, .dark)
        let hostingController = NSHostingController(rootView: contentView)
        panel.contentViewController = hostingController
    }
    
    @objc func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }
    
    private func openPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        
        // Size the panel to fit its content exactly
        guard let hostingView = panel.contentViewController?.view else { return }
        let panelWidth: CGFloat = 400
        hostingView.frame.size.width = panelWidth
        hostingView.layoutSubtreeIfNeeded()
        let panelHeight = hostingView.fittingSize.height
        
        // Position centered below the status bar button
        let panelX = screenRect.midX - panelWidth / 2
        let panelY = screenRect.minY - panelHeight - 4
        
        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        
        // Apply rounded corners on the window's backing layer
        if let windowView = panel.contentView?.superview {
            windowView.wantsLayer = true
            windowView.layer?.cornerRadius = 20
            windowView.layer?.cornerCurve = .continuous
            windowView.layer?.masksToBounds = true
        }
        
        panel.makeKeyAndOrderFront(nil)
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }
    
    private func closePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

/// An NSPanel subclass that can become the key window, allowing text fields to receive keyboard input.
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// An NSHostingView subclass that passes all mouse events through to its superview (the status bar button).
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
