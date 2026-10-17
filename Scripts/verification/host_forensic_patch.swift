import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore

let hueStep = 0.61803398875
let patchInterval = 2.0
let patchRectNormalized = CGRect(x: 0.08, y: 0.08, width: 0.20, height: 0.20)
let neutralGray = 0.5
let defaultForensicLifetimeSeconds = 3600.0
let defaultEscapeMarkerPath = NSHomeDirectory() + "/.config/sunshine/enchron-probe.escape"

let usage = "usage: host_forensic_patch [--window full|corner] [--escape-file <path>] [--log <path>] [--seconds <n>] [--exit-file <path>] [--freeze-file <path>] [--tone <hz>] [--tone-gain-db <db>] [--tone-period <sec>] [--tone-on <sec>] [--seed <uint64>] [--self-test]"

func currentWallMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
}

func hexText(_ value: UInt64, width: Int) -> String {
    let digits = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

func hexText(_ value: Int64, width: Int) -> String {
    let magnitude = value < 0 ? -value : value
    var digits = String(magnitude, radix: 16, uppercase: true)
    if value < 0 {
        digits = "-" + digits
    }
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

func hsvToRGB(hue: Double, saturation: Double, value: Double) -> (red: Double, green: Double, blue: Double) {
    let scaled = (hue - hue.rounded(.down)) * 6.0
    let sector = Int(scaled.rounded(.down)) % 6
    let fraction = scaled - scaled.rounded(.down)
    let p = value * (1.0 - saturation)
    let q = value * (1.0 - saturation * fraction)
    let t = value * (1.0 - saturation * (1.0 - fraction))
    switch sector {
    case 0: return (value, t, p)
    case 1: return (q, value, p)
    case 2: return (p, value, t)
    case 3: return (p, q, value)
    case 4: return (t, p, value)
    default: return (value, p, q)
    }
}

func patchHue(seed: UInt64, index: Int) -> Double {
    let seedFloat = Double(seed) / 18446744073709551616.0
    var hue = (seedFloat + Double(index) * hueStep).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 {
        hue += 1.0
    }
    return hue
}

func patchColor(seed: UInt64, index: Int) -> (red: Int, green: Int, blue: Int) {
    let rgb = hsvToRGB(hue: patchHue(seed: seed, index: index), saturation: 1.0, value: 1.0)
    return (
        Int((rgb.red * 255.0).rounded()),
        Int((rgb.green * 255.0).rounded()),
        Int((rgb.blue * 255.0).rounded())
    )
}

struct Options {
    var logPath: String?
    var seconds: Double?
    var exitFilePath: String?
    var freezeFilePath: String?
    var toneHz: Double?
    var toneGainDB: Double = -20.0
    var tonePeriod: Double = 0
    var toneOnSeconds: Double = 0.45
    var seed: UInt64?
    var selfTest = false
    var windowMode = "full"
    var escapeFilePath: String?
}

func parseOptions(_ arguments: [String]) -> Options? {
    var options = Options()
    var index = 0

    func nextValue(_ flag: String) -> String? {
        guard index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
            return nil
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--log":
            guard let value = nextValue(argument) else { return nil }
            options.logPath = value
        case "--seconds":
            guard let value = nextValue(argument), let seconds = Double(value), seconds > 0, seconds.isFinite else { return nil }
            options.seconds = seconds
        case "--exit-file":
            guard let value = nextValue(argument) else { return nil }
            options.exitFilePath = value
        case "--window":
            guard let value = nextValue(argument), value == "full" || value == "corner" else { return nil }
            options.windowMode = value
        case "--escape-file":
            guard let value = nextValue(argument) else { return nil }
            options.escapeFilePath = value
        case "--freeze-file":
            guard let value = nextValue(argument) else { return nil }
            options.freezeFilePath = value
        case "--tone":
            guard let value = nextValue(argument), let hertz = Double(value), hertz > 0, hertz < 20000 else { return nil }
            options.toneHz = hertz
        case "--tone-gain-db":
            guard let value = nextValue(argument), let decibels = Double(value), decibels.isFinite else { return nil }
            options.toneGainDB = decibels
        case "--tone-period":
            guard let value = nextValue(argument), let seconds = Double(value), seconds >= 0.2, seconds.isFinite else { return nil }
            options.tonePeriod = seconds
        case "--tone-on":
            guard let value = nextValue(argument), let seconds = Double(value), seconds > 0, seconds.isFinite else { return nil }
            options.toneOnSeconds = seconds
        case "--seed":
            guard let value = nextValue(argument), let seed = UInt64(value) else { return nil }
            options.seed = seed
        case "--self-test":
            options.selfTest = true
        default:
            FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
            return nil
        }
        index += 1
    }
    return options
}

final class EventLog {
    private let handle: FileHandle?
    private let lock = NSLock()

    init(path: String?) {
        guard let path, !path.isEmpty else {
            handle = nil
            return
        }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let opened = try? FileHandle(forWritingTo: url)
        opened?.seekToEndOfFile()
        handle = opened
        if opened == nil {
            FileHandle.standardError.write(Data("log: cannot open \(path)\n".utf8))
        }
    }

    @discardableResult
    func write(_ event: [String: Any], echo: Bool = false) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("log: event not serializable\n".utf8))
            return nil
        }
        let payload = Data((line + "\n").utf8)
        lock.lock()
        if let handle {
            handle.write(payload)
            _ = try? handle.synchronize()
        }
        lock.unlock()
        if echo {
            FileHandle.standardOutput.write(payload)
        }
        return line
    }
}

let mouseEventTypes: [CGEventType] = [
    .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
]

let monitoredEventTypes: [CGEventType] = mouseEventTypes + [
    .scrollWheel, .keyDown, .keyUp, .flagsChanged,
]

let monitoredEventMask: CGEventMask = monitoredEventTypes.reduce(CGEventMask(0)) { mask, type in
    mask | (CGEventMask(1) << CGEventMask(type.rawValue))
}

let monitoredEventTypeMask: NSEvent.EventTypeMask = [
    .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    .scrollWheel, .keyDown, .keyUp, .flagsChanged,
]

func inputKind(for type: CGEventType) -> String {
    switch type {
    case .null: return "null"
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .mouseMoved: return "mouseMoved"
    case .leftMouseDragged: return "leftMouseDragged"
    case .rightMouseDragged: return "rightMouseDragged"
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    case .flagsChanged: return "flagsChanged"
    case .scrollWheel: return "scrollWheel"
    case .tabletPointer: return "tabletPointer"
    case .tabletProximity: return "tabletProximity"
    case .otherMouseDown: return "otherMouseDown"
    case .otherMouseUp: return "otherMouseUp"
    case .otherMouseDragged: return "otherMouseDragged"
    case .tapDisabledByTimeout: return "tapDisabledByTimeout"
    case .tapDisabledByUserInput: return "tapDisabledByUserInput"
    default: return "eventType\(type.rawValue)"
    }
}

func unicodeString(of event: CGEvent) -> String {
    var characters = [UniChar](repeating: 0, count: 128)
    var length = 0
    characters.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        event.keyboardGetUnicodeString(maxStringLength: 128, actualStringLength: &length, unicodeString: base)
    }
    guard length > 0 else { return "" }
    return String(utf16CodeUnits: characters, count: min(length, characters.count))
}

func formatInputEvent(_ event: CGEvent, kind: CGEventType? = nil, source: String) -> [String: Any] {
    let type = kind ?? event.type
    let isMouse = mouseEventTypes.contains(type)
    let isScroll = type == .scrollWheel
    let isKey = type == .keyDown || type == .keyUp || type == .flagsChanged
    let location = event.location
    return [
        "event": "input",
        "source": source,
        "kind": inputKind(for: type),
        "typeRaw": Int(type.rawValue),
        "wallMs": currentWallMs(),
        "eventTimestampNs": Int64(bitPattern: event.timestamp),
        "sourcePid": event.getIntegerValueField(.eventSourceUnixProcessID),
        "sourceStateId": event.getIntegerValueField(.eventSourceStateID),
        "userData": event.getIntegerValueField(.eventSourceUserData),
        "targetPid": event.getIntegerValueField(.eventTargetUnixProcessID),
        "x": Double(location.x),
        "y": Double(location.y),
        "button": isMouse || isScroll ? event.getIntegerValueField(.mouseEventButtonNumber) : 0,
        "deltaX": isScroll ? event.getDoubleValueField(.scrollWheelEventDeltaAxis2) : 0.0,
        "deltaY": isScroll ? event.getDoubleValueField(.scrollWheelEventDeltaAxis1) : 0.0,
        "deltaYPoint": isScroll ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : 0.0,
        "keycode": isKey ? event.getIntegerValueField(.keyboardEventKeycode) : 0,
        "flags": Int64(bitPattern: event.flags.rawValue),
        "unicode": isKey && type != .flagsChanged ? unicodeString(of: event) : "",
        "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
    ]
}

final class InputMonitor {
    private let log: EventLog
    private(set) var mode = "disabled"
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(log: EventLog) {
        self.log = log
    }

    func start() {
        let mask = monitoredEventMask
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hostForensicTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            self.tap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            mode = "tap"
            log.write([
                "event": "tap",
                "action": "start",
                "mode": mode,
                "listenAccess": CGPreflightListenEventAccess(),
                "eventMask": hexText(Int64(mask), width: 4),
                "wallMs": currentWallMs(),
            ])
            return
        }
        mode = "nsEvent"
        FileHandle.standardError.write(Data("input: CGEventTap creation failed, using NSEvent monitors\n".utf8))
        log.write([
            "event": "tap",
            "action": "start",
            "mode": mode,
            "reason": "tapCreate-failed",
            "listenAccess": CGPreflightListenEventAccess(),
            "wallMs": currentWallMs(),
        ])
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: monitoredEventTypeMask) { [weak self] event in
            self?.handle(nsEvent: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: monitoredEventTypeMask) { [weak self] event in
            self?.handle(nsEvent: event)
            return event
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        tap = nil
        runLoopSource = nil
        globalMonitor = nil
        localMonitor = nil
    }

    func handle(event: CGEvent, type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            log.write([
                "event": "tap",
                "action": "re-enabled",
                "kind": inputKind(for: type),
                "wallMs": currentWallMs(),
            ])
            return
        }
        log.write(formatInputEvent(event, kind: type, source: "tap"))
    }

    func handle(nsEvent event: NSEvent) {
        if let cgEvent = event.cgEvent {
            log.write(formatInputEvent(cgEvent, source: "nsEvent"))
            return
        }
        log.write([
            "event": "input",
            "source": "nsEvent",
            "kind": "nsEventType\(event.type.rawValue)",
            "typeRaw": Int(event.type.rawValue),
            "wallMs": currentWallMs(),
            "eventTimestampNs": Int64(event.timestamp * 1_000_000_000.0),
            "sourcePid": 0,
            "sourceStateId": 0,
            "userData": 0,
            "targetPid": 0,
            "x": Double(event.locationInWindow.x),
            "y": Double(event.locationInWindow.y),
            "button": Int64(event.buttonNumber),
            "deltaX": Double(event.scrollingDeltaX),
            "deltaY": Double(event.scrollingDeltaY),
            "deltaYPoint": 0.0,
            "keycode": Int64(event.keyCode),
            "flags": Int64(event.modifierFlags.rawValue),
            "unicode": event.charactersIgnoringModifiers ?? "",
            "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
        ])
    }
}

func hostForensicTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(event: event, type: type)
    }
    return Unmanaged.passUnretained(event)
}

final class TonePlayer {
    private let log: EventLog
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var hertz: Double = 0
    private var running = false

    init(log: EventLog) {
        self.log = log
    }

    func start(hertz: Double, gainDB: Double, periodSeconds: Double, onSeconds: Double) {
        let sampleRate = 48000.0
        let capacity = periodSeconds > 0 ? periodSeconds * sampleRate : sampleRate
        let onFrames = periodSeconds > 0 ? min(onSeconds, periodSeconds) * sampleRate : capacity
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)),
              let channels = buffer.floatChannelData else {
            FileHandle.standardError.write(Data("tone: buffer allocation failed\n".utf8))
            log.write(["event": "tone", "action": "error", "hz": hertz, "wallMs": currentWallMs()])
            return
        }
        buffer.frameLength = buffer.frameCapacity
        let increment = 2.0 * Double.pi * hertz / sampleRate
        let toneFrames = Int(onFrames)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                channels[channel][frame] = frame < toneFrames
                    ? Float(sin(increment * Double(frame)))
                    : 0
            }
        }
        do {
            engine.attach(player)
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
            player.volume = Float(pow(10.0, gainDB / 20.0))
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            try engine.start()
            _ = try player.playAudio()
            running = true
            self.hertz = hertz
            log.write([
                "event": "tone",
                "action": "start",
                "hz": hertz,
                "gainDB": gainDB,
                "periodSeconds": periodSeconds,
                "onSeconds": periodSeconds > 0 ? onSeconds : 0,
                "sampleRate": sampleRate,
                "wallMs": currentWallMs(),
            ])
        } catch {
            FileHandle.standardError.write(Data("tone: engine start failed: \(error)\n".utf8))
            log.write(["event": "tone", "action": "error", "hz": hertz, "wallMs": currentWallMs()])
        }
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        running = false
        log.write([
            "event": "tone",
            "action": "stop",
            "hz": hertz,
            "wallMs": currentWallMs(),
        ])
    }
}

final class PatchView: NSView {
    private let patchLayer = CALayer()
    private let hudField = NSTextField(labelWithString: "")
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    var desktopSize = NSSize.zero
    var desktopTopOffset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: neutralGray, alpha: 1.0).cgColor
        patchLayer.backgroundColor = NSColor.black.cgColor
        patchLayer.magnificationFilter = .nearest
        patchLayer.minificationFilter = .nearest
        patchLayer.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.addSublayer(patchLayer)
        hudField.font = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .semibold)
        hudField.textColor = .white
        hudField.drawsBackground = true
        hudField.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.72)
        hudField.isBezeled = false
        hudField.isEditable = false
        hudField.isSelectable = false
        hudField.usesSingleLineMode = true
        hudField.maximumNumberOfLines = 1
        hudField.lineBreakMode = .byTruncatingTail
        hudField.wantsLayer = true
        addSubview(hudField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unused")
    }

    var patchColor: NSColor {
        get { NSColor(cgColor: patchLayer.backgroundColor ?? NSColor.black.cgColor) ?? .black }
        set {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            patchLayer.backgroundColor = newValue.cgColor
            CATransaction.commit()
        }
    }

    var hudText: String {
        get { hudField.stringValue }
        set { hudField.stringValue = newValue }
    }

    override func layout() {
        super.layout()
        let reference = desktopSize.width > 0 && desktopSize.height > 0 ? desktopSize : bounds.size
        let patchX = (patchRectNormalized.minX * reference.width).rounded()
        let patchY = (bounds.height - (patchRectNormalized.maxY * reference.height - desktopTopOffset)).rounded()
        let patchWidth = (patchRectNormalized.width * reference.width).rounded()
        let patchHeight = (patchRectNormalized.height * reference.height).rounded()
        patchLayer.frame = CGRect(x: patchX, y: patchY, width: patchWidth, height: patchHeight)
        let stripHeight = max(16.0, patchY - 4.0)
        hudField.frame = CGRect(x: 8.0, y: 2.0, width: max(0.0, bounds.width - 16.0), height: stripHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        patchLayer.contentsScale = scale
        hudField.layer?.contentsScale = scale
        needsLayout = true
    }
}

final class ForensicController: NSObject {
    private let options: Options
    private let log: EventLog
    private let input: InputMonitor
    private let tone: TonePlayer
    private let seed: UInt64
    private let lifetimeSeconds: Double
    private var window: NSWindow?
    private var view: PatchView?
    private var displayLink: CADisplayLink?
    private var frameTimerSource: DispatchSourceTimer?
    private var timers: [Timer] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var frameCounter: UInt64 = 0
    private var patchIndex = -1
    private var patchRGB: (red: Int, green: Int, blue: Int) = (0, 0, 0)
    private var startMediaTime: Double = 0
    private var lastTickMediaTime: Double = 0
    private var frozenAccumulated: Double = 0
    private var shuttingDown = false

    init(options: Options) {
        self.options = options
        let log = EventLog(path: options.logPath)
        self.log = log
        self.input = InputMonitor(log: log)
        self.tone = TonePlayer(log: log)
        self.lifetimeSeconds = options.seconds ?? defaultForensicLifetimeSeconds
        self.seed = options.seed ?? UInt64.random(in: UInt64.min...UInt64.max)
    }

    func run() {
        log.write([
            "event": "seed",
            "seed": seed,
            "seedHex": hexText(seed, width: 16),
            "wallMs": currentWallMs(),
        ], echo: true)

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? NSScreen.screens.first else {
            log.write(["event": "error", "message": "no screen available", "wallMs": currentWallMs()])
            exit(3)
        }

        let fullScreen = options.windowMode != "corner"
        let cornerFraction = max(patchRectNormalized.maxX, patchRectNormalized.maxY) + 0.04
        let windowSize = fullScreen
            ? screen.frame.size
            : NSSize(
                width: (cornerFraction * screen.frame.width).rounded(),
                height: (cornerFraction * screen.frame.height).rounded()
            )
        let windowOrigin = fullScreen
            ? screen.frame.origin
            : NSPoint(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y + screen.frame.height - windowSize.height
            )
        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedWhite: neutralGray, alpha: 1.0)
        window.hasShadow = false
        window.level = fullScreen
            ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            : .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        window.animationBehavior = .none
        window.ignoresMouseEvents = !fullScreen
        window.acceptsMouseMovedEvents = fullScreen
        window.isMovable = false
        window.isReleasedWhenClosed = false

        let view = PatchView(frame: NSRect(origin: .zero, size: windowSize))
        view.desktopSize = screen.frame.size
        window.contentView = view
        window.setFrame(NSRect(origin: windowOrigin, size: windowSize), display: true)
        if fullScreen {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            application.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
        view.desktopTopOffset = screen.frame.maxY - window.frame.maxY
        view.layoutSubtreeIfNeeded()

        view.onEscape = { [weak self] in
            guard let self else { return }
            self.log.write(["event": "escape-abort", "wallMs": currentWallMs()], echo: true)
            let marker = self.options.escapeFilePath ?? defaultEscapeMarkerPath
            try? "escape".write(toFile: marker, atomically: true, encoding: .utf8)
            self.shutdown(reason: "escape")
        }
        try? FileManager.default.removeItem(atPath: options.escapeFilePath ?? defaultEscapeMarkerPath)

        self.window = window
        self.view = view

        log.write([
            "event": "launch",
            "pid": Int(getpid()),
            "seed": seed,
            "wallMs": currentWallMs(),
            "screenFrame": [
                "x": Double(screen.frame.origin.x),
                "y": Double(screen.frame.origin.y),
                "width": Double(screen.frame.width),
                "height": Double(screen.frame.height),
            ],
            "backingScaleFactor": Double(screen.backingScaleFactor),
            "screenFramePixels": [
                "width": Double(screen.frame.width * screen.backingScaleFactor),
                "height": Double(screen.frame.height * screen.backingScaleFactor),
            ],
            "patchRectNormalized": [
                "x": Double(patchRectNormalized.minX),
                "y": Double(patchRectNormalized.minY),
                "width": Double(patchRectNormalized.width),
                "height": Double(patchRectNormalized.height),
            ],
            "logPath": options.logPath ?? "",
            "toneHz": options.toneHz ?? 0,
            "seconds": options.seconds ?? 0,
            "lifetimeSeconds": lifetimeSeconds,
            "patchWindowFrame": [
                "x": Double(window.frame.origin.x),
                "y": Double(window.frame.origin.y),
                "width": Double(window.frame.width),
                "height": Double(window.frame.height),
            ],
            "windowIgnoresMouse": window.ignoresMouseEvents,
            "windowLevel": Int(window.level.rawValue),
            "listenAccess": CGPreflightListenEventAccess(),
            "postEventAccess": CGPreflightPostEventAccess(),
            "screenCaptureAccess": CGPreflightScreenCaptureAccess(),
        ])

        input.start()
        log.write([
            "event": "input-monitor",
            "mode": input.mode,
            "wallMs": currentWallMs(),
        ])

        if let hertz = options.toneHz {
            tone.start(
                hertz: hertz,
                gainDB: options.toneGainDB,
                periodSeconds: options.tonePeriod,
                onSeconds: min(options.toneOnSeconds, max(options.tonePeriod, options.toneOnSeconds))
            )
        }

        installSignalHandlers()
        startMediaTime = CACurrentMediaTime()
        applyPatch(index: 0)
        updateHUD()
        startDisplayLink()
        startTimers()
        startFrameSourceWatchdog()

        application.run()
    }

    private func startDisplayLink() {
        guard let view else { return }
        let link = view.displayLink(target: self, selector: #selector(displayTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        log.write([
            "event": "frames-source",
            "source": "display-link",
            "action": "start",
            "maximumFramesPerSecond": Int(NSScreen.main?.maximumFramesPerSecond ?? 0),
            "wallMs": currentWallMs(),
        ])
    }

    private func startFrameSourceWatchdog() {
        let watchdog = Timer(timeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.frameCounter > 0 {
                self.log.write([
                    "event": "frames-source",
                    "source": "display-link",
                    "action": "confirmed",
                    "counter": self.frameCounter,
                    "wallMs": currentWallMs(),
                ])
                return
            }
            self.log.write([
                "event": "frames-source",
                "source": "timer-120hz",
                "action": "fallback",
                "reason": "display-link-silent",
                "wallMs": currentWallMs(),
            ])
            self.displayLink?.invalidate()
            self.displayLink = nil
            let source = DispatchSource.makeTimerSource(queue: .main)
            source.schedule(deadline: .now(), repeating: 1.0 / 120.0, leeway: .milliseconds(1))
            source.setEventHandler { [weak self] in
                self?.displayTick()
            }
            source.resume()
            self.frameTimerSource = source
        }
        RunLoop.main.add(watchdog, forMode: .common)
        timers.append(watchdog)
    }

    @objc private func displayTick() {
        frameCounter += 1
        let now = CACurrentMediaTime()
        if lastTickMediaTime == 0 {
            lastTickMediaTime = now
        }
        let delta = max(0, now - lastTickMediaTime)
        lastTickMediaTime = now
        if let freezeFilePath = options.freezeFilePath,
           FileManager.default.fileExists(atPath: freezeFilePath) {
            frozenAccumulated += delta
        }
        let elapsed = now - startMediaTime - frozenAccumulated
        let index = Int((elapsed / patchInterval).rounded(.down))
        if index > patchIndex {
            applyPatch(index: index)
        }
        updateHUD()
    }

    private func applyPatch(index: Int) {
        let rgb = patchColor(seed: seed, index: index)
        patchIndex = index
        patchRGB = rgb
        view?.patchColor = NSColor(
            srgbRed: CGFloat(rgb.red) / 255.0,
            green: CGFloat(rgb.green) / 255.0,
            blue: CGFloat(rgb.blue) / 255.0,
            alpha: 1.0
        )
        log.write([
            "event": "patch",
            "index": index,
            "rgb": [rgb.red, rgb.green, rgb.blue],
            "rgbHex": "#" + hexText(Int64(rgb.red), width: 2) + hexText(Int64(rgb.green), width: 2) + hexText(Int64(rgb.blue), width: 2),
            "displayedAtWallMs": currentWallMs(),
        ])
    }

    private func updateHUD() {
        let rgb = patchRGB
        let remaining = max(0, Int((lifetimeSeconds - (CACurrentMediaTime() - startMediaTime)).rounded()))
        let text = "FRAME " + hexText(Int64(frameCounter), width: 8)
            + " · PATCH " + String(patchIndex)
            + " #" + hexText(Int64(rgb.red), width: 2) + hexText(Int64(rgb.green), width: 2) + hexText(Int64(rgb.blue), width: 2)
            + " · 取证窗口 " + String(remaining) + "s 后自动关闭"
        view?.hudText = text
    }

    private func startTimers() {
        let frames = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.log.write([
                "event": "frames",
                "counter": self.frameCounter,
                "wallMs": currentWallMs(),
                "patchIndex": self.patchIndex,
            ])
        }
        RunLoop.main.add(frames, forMode: .common)
        timers.append(frames)

        if options.exitFilePath != nil {
            let poll = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, let path = self.options.exitFilePath else { return }
                if FileManager.default.fileExists(atPath: path) {
                    self.shutdown(reason: "exit-file")
                }
            }
            RunLoop.main.add(poll, forMode: .common)
            timers.append(poll)
        }

        let deadline = Timer(timeInterval: lifetimeSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.shutdown(reason: self.options.seconds != nil ? "seconds" : "lifetime-cap")
        }
        RunLoop.main.add(deadline, forMode: .common)
        timers.append(deadline)
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutdown(reason: signalNumber == SIGTERM ? "sigterm" : "sigint")
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func shutdown(reason: String) {
        if shuttingDown {
            return
        }
        shuttingDown = true
        displayLink?.invalidate()
        displayLink = nil
        frameTimerSource?.cancel()
        frameTimerSource = nil
        for timer in timers {
            timer.invalidate()
        }
        timers.removeAll()
        tone.stop()
        input.stop()
        log.write([
            "event": "exit",
            "reason": reason,
            "pid": Int(getpid()),
            "wallMs": currentWallMs(),
            "frames": frameCounter,
            "patchIndex": patchIndex,
        ], echo: true)
        exit(0)
    }
}

func serializeRoundTrip(_ event: [String: Any]) -> [String: Any]? {
    guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return object
}

func runSelfTest() -> Int32 {
    var report: [String] = []
    var failures: [String] = []

    let seed: UInt64 = 0x8F3A2C119D456E70
    let sequence = (0..<5).map { patchColor(seed: seed, index: $0) }
    let repeated = (0..<5).map { patchColor(seed: seed, index: $0) }
    let sequenceValues = sequence.map { [$0.red, $0.green, $0.blue] }
    let repeatedValues = repeated.map { [$0.red, $0.green, $0.blue] }
    if sequenceValues == repeatedValues {
        report.append("determinism: same seed reproduces the first 5 colors \(sequenceValues)")
    } else {
        failures.append("determinism: same seed produced different colors")
    }

    let otherSeed = (0..<5).map { patchColor(seed: seed ^ 0x5555555555555555, index: $0) }
    let otherValues = otherSeed.map { [$0.red, $0.green, $0.blue] }
    if otherValues != sequenceValues {
        report.append("seed sensitivity: another seed produces another sequence \(otherValues)")
    } else {
        failures.append("seed sensitivity: sequence ignores the seed")
    }

    var minimumHueDistance = 1.0
    for index in 1..<12 {
        let previous = patchHue(seed: seed, index: index - 1)
        let current = patchHue(seed: seed, index: index)
        let rawDifference = abs(current - previous)
        minimumHueDistance = min(minimumHueDistance, min(rawDifference, 1.0 - rawDifference))
    }

    var minimumChannelDelta = 255
    for index in 1..<12 {
        let previous = patchColor(seed: seed, index: index - 1)
        let current = patchColor(seed: seed, index: index)
        let delta = max(
            abs(current.red - previous.red),
            max(abs(current.green - previous.green), abs(current.blue - previous.blue))
        )
        minimumChannelDelta = min(minimumChannelDelta, delta)
    }

    if minimumHueDistance >= 0.30 && minimumChannelDelta >= 50 {
        report.append("separation: minimum hue distance \(String(format: "%.4f", minimumHueDistance)), minimum channel delta \(minimumChannelDelta)")
    } else {
        failures.append("separation too small: hue \(minimumHueDistance), channel \(minimumChannelDelta)")
    }

    let logPath = NSTemporaryDirectory() + "enchron-forensic-selftest-\(getpid()).jsonl"
    try? FileManager.default.removeItem(atPath: logPath)
    let log = EventLog(path: logPath)
    log.write(["event": "launch", "pid": Int(getpid()), "seed": seed, "wallMs": currentWallMs()])
    log.write(["event": "frames", "counter": 7, "wallMs": currentWallMs()])
    var parsedLines = 0
    var seedRoundTrip = false
    if let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)), let contents = String(data: data, encoding: .utf8) {
        for line in contents.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                failures.append("jsonl: unparseable line \(line)")
                continue
            }
            parsedLines += 1
            if object["event"] as? String == "launch", let value = object["seed"] as? NSNumber {
                seedRoundTrip = value.uint64Value == seed
            }
        }
    } else {
        failures.append("jsonl: log file unreadable")
    }
    if parsedLines == 2 && seedRoundTrip {
        report.append("jsonl: 2 lines parse back, 64-bit seed \(seed) round-trips exactly")
    } else {
        failures.append("jsonl: parsed \(parsedLines) lines, seed round-trip \(seedRoundTrip)")
    }
    try? FileManager.default.removeItem(atPath: logPath)

    var formatted: [[String: Any]] = []
    var mouseOk = false
    var keyOk = false
    if let mouse = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 321.5, y: 654.25), mouseButton: .left) {
        if let object = serializeRoundTrip(formatInputEvent(mouse, source: "selftest")) {
            formatted.append(object)
            mouseOk = (object["kind"] as? String) == "leftMouseDown"
                && (object["x"] as? Double) == 321.5
                && (object["y"] as? Double) == 654.25
                && (object["sourcePid"] as? NSNumber)?.uint64Value == UInt64(getpid())
        } else {
            failures.append("input: mouse event not serializable")
        }
    } else {
        failures.append("input: synthetic mouse event unavailable")
    }
    if let key = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true) {
        key.keyboardSetUnicodeString(stringLength: 2, unicodeString: [79, 75])
        if let object = serializeRoundTrip(formatInputEvent(key, source: "selftest")) {
            formatted.append(object)
            keyOk = (object["kind"] as? String) == "keyDown"
                && (object["unicode"] as? String) == "OK"
                && (object["keycode"] as? NSNumber)?.intValue == 12
        } else {
            failures.append("input: key event not serializable")
        }
    } else {
        failures.append("input: synthetic key event unavailable")
    }

    let requiredKeys = [
        "event", "kind", "wallMs", "sourcePid", "sourceStateId", "userData",
        "targetPid", "x", "y", "button", "deltaY", "keycode", "flags", "unicode",
    ]
    var missingSummary: [String] = []
    for object in formatted {
        let missing = requiredKeys.filter { object[$0] == nil }
        if !missing.isEmpty {
            missingSummary.append("\(object["kind"] ?? "?") -> \(missing)")
        }
    }
    if formatted.count == 2 && missingSummary.isEmpty {
        report.append("input: \(formatted.count) synthetic events carry all required fields (\(requiredKeys.count) keys)")
    } else {
        failures.append("input: field check failed \(missingSummary)")
    }
    if mouseOk {
        report.append("input: mouse coordinates and source pid survive the encoder")
    } else {
        failures.append("input: mouse coordinates or source pid lost")
    }
    if keyOk {
        report.append("input: key event keeps keycode 12 and unicode \"OK\"")
    } else {
        failures.append("input: key event lost keycode or unicode")
    }

    for line in report {
        print("PASS \(line)")
    }
    for line in failures {
        print("FAIL \(line)")
    }
    if failures.isEmpty {
        print("SELFTEST OK")
        return 0
    }
    print("SELFTEST FAILED")
    return 1
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let options = parseOptions(arguments) else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
if options.selfTest {
    exit(runSelfTest())
}
let controller = ForensicController(options: options)
controller.run()
