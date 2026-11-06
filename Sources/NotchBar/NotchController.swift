import AppKit
import SwiftUI
import Combine

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HoverSensorPanel: NSPanel {
    var onEnter: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor(white: 0, alpha: 0.01)
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        let view = SensorView()
        view.onEnter = { [weak self] in self?.onEnter?() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SensorView: NSView {
    var onEnter: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseDown(with event: NSEvent) { onEnter?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchController {
    let vm: NotchViewModel
    private let panel = NotchPanel()
    private let sensor = HoverSensorPanel()
    private var vmObserver: AnyCancellable?
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?

    init(music: MusicManager, clipboard: ClipboardManager, docker: DockerManager) {
        let (screen, notchSize) = Self.detectNotch()
        vm = NotchViewModel(music: music, notchSize: notchSize, screenFrame: screen.frame)

        let host = FirstMouseHostingView(rootView: NotchView(vm: vm, music: music, clipboard: clipboard, docker: docker))
        host.sizingOptions = []
        panel.contentView = host

        vm.onExpandedChange = { [weak docker] open in docker?.setWatching(open) }
        clipboard.onNewItem = { [weak vm] item in vm?.showPeek(item) }

        sensor.onEnter = { [weak self] in
            MainActor.assumeIsolated { self?.sensorEntered() }
        }

        layout(on: screen)
        sensor.orderFrontRegardless()
        panel.orderFrontRegardless()
        updateSensor()
        vmObserver = vm.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateSensor() }
        }
    }

    private func updateSensor() {
        guard !vm.isExpanded else { return }
        let r = vm.hitRect(padding: 4)
        if sensor.frame != r { sensor.setFrame(r, display: false) }
    }

    private func sensorEntered() {
        installMouseMonitors()
        handleMouse()
    }

    func relayout() {
        let (screen, notchSize) = Self.detectNotch()
        vm.notchSize = notchSize
        vm.screenFrame = screen.frame
        layout(on: screen)
        updateSensor()
    }

    private func layout(on screen: NSScreen) {
        let w = vm.expandedSize.width + 120
        let h = vm.expandedSize.height + 60
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        panel.setFrame(frame, display: true)
    }

    static func detectNotch() -> (NSScreen, CGSize) {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens[0]

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return (screen, CGSize(width: width, height: screen.safeAreaInsets.top))
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return (screen, CGSize(width: 190, height: max(menuBar, NSStatusBar.system.thickness, 24)))
    }


    private func installMouseMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse() }
            return event
        }) { monitors.append(l) }
    }

    private func removeMouseMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func collapse() {
        vm.isExpanded = false
        panel.ignoresMouseEvents = true
        removeMouseMonitors()
        updateSensor()
    }

    private static var mouseHeld: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    private func handleMouse() {
        let p = NSEvent.mouseLocation
        let inside = vm.hitRect(padding: vm.isExpanded ? 10 : 4).contains(p)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !vm.isExpanded {
                if vm.peek != nil { vm.tab = .clipboard; vm.peek = nil }
                vm.isExpanded = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else if !vm.isExpanded {
            removeMouseMonitors()
        } else if collapseWork == nil && !Self.mouseHeld {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                if !Self.mouseHeld && !self.vm.hitRect(padding: 10).contains(NSEvent.mouseLocation) {
                    self.collapse()
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
        let ignore = !(vm.isExpanded && inside)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }
}
