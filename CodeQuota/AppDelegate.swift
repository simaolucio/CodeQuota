import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Create custom icon view that passes through mouse events
            let iconView = UsageIconView()
            let hostingView = ClickThroughHostingView(rootView: iconView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 80, height: 22)
            button.addSubview(hostingView)
            button.frame = hostingView.frame
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover with transparent/vibrancy content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 540)
        popover.behavior = .transient
        
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)
        
        // Make the hosting view's layer transparent so the vibrancy shows through
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        popover.contentViewController = hostingController
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                
                // Apply vibrancy to the popover's content view after it's shown
                if let contentView = popover.contentViewController?.view {
                    applyVibrancy(to: contentView)
                }
            }
        }
    }
    
    private func applyVibrancy(to view: NSView) {
        // Check if we already added a visual effect view
        if view.subviews.first(where: { $0 is NSVisualEffectView }) != nil {
            return
        }
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        
        // Insert the visual effect view behind all other content
        view.addSubview(visualEffect, positioned: .below, relativeTo: view.subviews.first)
        
        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

/// An NSHostingView subclass that passes all mouse events through to its superview (the status bar button).
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
