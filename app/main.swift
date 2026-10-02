// Hint mode for the whole Claude Desktop window, driven through the macOS
// Accessibility API: the web UI and the app chrome both appear in the AX tree,
// which no mod surface reaches. Runs as a menu bar app; the vimium-hints mod
// reaches it through the claude-vimium:// URL scheme.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

let claudeBundleID = "com.anthropic.claudefordesktop"
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let accessibilitySettings = URL(
  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

if CommandLine.arguments.dropFirst().contains("--version") {
  print("claude-vimium \(appVersion)")
  exit(0)
}

// `claude-vimium doctor` reads this file: the app's own trust state is not
// observable from another process.
let logURL = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Logs/claude-vimium/app.log")

func log(_ message: String) {
  let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
  try? FileManager.default.createDirectory(
    at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  if let handle = try? FileHandle(forWritingTo: logURL) {
    handle.seekToEndOfFile()
    handle.write(line.data(using: .utf8)!)
    try? handle.close()
  } else {
    try? line.write(to: logURL, atomically: true, encoding: .utf8)
  }
}

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
  var value: AnyObject?
  return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func frame(of element: AXUIElement) -> CGRect? {
  guard let p = attr(element, kAXPositionAttribute), let s = attr(element, kAXSizeAttribute) else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  AXValueGetValue(p as! AXValue, .cgPoint, &point)
  AXValueGetValue(s as! AXValue, .cgSize, &size)
  return CGRect(origin: point, size: size)
}

struct Target {
  let element: AXUIElement
  let role: String
  let rect: CGRect  // AX space: top-left origin of the primary screen
}

func collectTargets(in window: AXUIElement) -> [Target] {
  var targets: [Target] = []
  var visited = 0
  func walk(_ element: AXUIElement, clip: CGRect, depth: Int) {
    visited += 1
    if depth > 80 || visited > 30000 { return }
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    var clip = clip
    let rect = frame(of: element)
    if clipRoles.contains(role), let rect { clip = clip.intersection(rect) }
    if clip.isNull || clip.isEmpty { return }
    if isHintable(role: role, subrole: attr(element, kAXSubroleAttribute) as? String), let rect,
      rect.width > 2, rect.height > 2
    {
      let visible = rect.intersection(clip)
      if !visible.isNull, visible.width > 2, visible.height > 2,
        !targets.contains(where: { abs($0.rect.minX - visible.minX) < 2 && abs($0.rect.minY - visible.minY) < 2 })
      {
        targets.append(Target(element: element, role: role, rect: visible))
      }
    }
    for child in (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
      walk(child, clip: clip, depth: depth + 1)
    }
  }
  guard let windowRect = frame(of: window) else { return [] }
  walk(window, clip: windowRect, depth: 0)
  return targets.sorted { abs($0.rect.minY - $1.rect.minY) > 4 ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
}

final class HintView: NSView {
  var hints: [(label: String, origin: CGPoint)] = []
  var typed = ""
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    for hint in hints where hint.label.hasPrefix(typed) {
      let text = NSMutableAttributedString(
        string: hint.label.uppercased(), attributes: [.font: font, .foregroundColor: NSColor.black])
      text.addAttribute(
        .foregroundColor, value: NSColor(calibratedRed: 0.55, green: 0.4, blue: 0, alpha: 1),
        range: NSRange(location: 0, length: typed.count))
      let size = text.size()
      let box = NSRect(x: hint.origin.x, y: hint.origin.y, width: size.width + 6, height: size.height + 2)
      NSColor(calibratedRed: 1, green: 0.85, blue: 0.25, alpha: 0.95).setFill()
      NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
      NSColor(calibratedWhite: 0, alpha: 0.35).setStroke()
      NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).stroke()
      text.draw(at: NSPoint(x: box.minX + 3, y: box.minY + 1))
    }
  }
}

// Keys come from an event tap, not the panel: a non-activating panel of a
// background app does not reliably become key, and the keys then land in
// Claude, where a typed hint letter goes into the composer.
final class HintMode {
  private var panel: NSPanel?
  private var view: HintView?
  private var tap: CFMachPort?
  private var targets: [String: Target] = [:]
  private var window: AXUIElement?
  private var observer: AXObserver?
  private var pendingRefresh: DispatchWorkItem?
  var isActive: Bool { panel != nil }

  func toggle() { isActive ? exit() : enter() }

  func enter() {
    guard AXIsProcessTrusted() else {
      log("hint mode: accessibility not granted")
      NSWorkspace.shared.open(accessibilitySettings)
      return
    }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first else { return }
    // The tap swallows every key, so hint mode starts only over a frontmost Claude.
    if !app.isActive {
      app.activate()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        if app.isActive, self?.isActive == false { self?.enter() }
      }
      return
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    // Chromium builds its web AX tree only once an assistive client asks.
    AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    guard let window = (attr(root, kAXFocusedWindowAttribute) as! AXUIElement?)
      ?? (attr(root, kAXWindowsAttribute) as? [AXUIElement])?.first,
      let windowRect = frame(of: window)
    else { return }
    self.window = window
    observe(window, pid: app.processIdentifier)
    show(windowRect: windowRect, found: collectTargets(in: window))
  }

  private func show(windowRect: CGRect, found: [Target]) {
    let labels = generateLabels(found.count)
    targets = Dictionary(uniqueKeysWithValues: zip(labels, found))
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let cocoaFrame = NSRect(
      x: windowRect.minX, y: primaryHeight - windowRect.maxY, width: windowRect.width, height: windowRect.height)

    let panel = self.panel ?? NSPanel(
      contentRect: cocoaFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.setFrame(cocoaFrame, display: false)
    panel.level = .statusBar
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let view = self.view ?? HintView(frame: NSRect(origin: .zero, size: cocoaFrame.size))
    view.frame = NSRect(origin: .zero, size: cocoaFrame.size)
    view.typed = ""
    view.hints = targets.map { label, target in
      (label, CGPoint(x: target.rect.minX - windowRect.minX, y: target.rect.minY - windowRect.minY))
    }
    panel.contentView = view
    panel.orderFrontRegardless()
    view.needsDisplay = true
    self.panel = panel
    self.view = view
    if tap == nil { startTap() }
  }

  func exit() {
    panel?.orderOut(nil)
    panel = nil
    view = nil
    targets = [:]
    pendingRefresh?.cancel()
    if let observer {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
      self.observer = nil
    }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      self.tap = nil
    }
  }

  // Labels sit at absolute positions, so a moved or resized window needs them measured again.
  private func observe(_ window: AXUIElement, pid: pid_t) {
    var created: AXObserver?
    let callback: AXObserverCallback = { _, _, _, info in
      Unmanaged<HintMode>.fromOpaque(info!).takeUnretainedValue().scheduleRefresh()
    }
    guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
    let me = Unmanaged.passUnretained(self).toOpaque()
    for name in [kAXMovedNotification, kAXResizedNotification] {
      AXObserverAddNotification(observer, window, name as CFString, me)
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    self.observer = observer
  }

  private func scheduleRefresh(after delay: TimeInterval = 0.2) {
    pendingRefresh?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.isActive, let window = self.window, let rect = frame(of: window) else { return }
      self.show(windowRect: rect, found: collectTargets(in: window))
    }
    pendingRefresh = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  // An active (filtering) tap needs only the Accessibility grant the app
  // already holds; a listen-only one would need Input Monitoring as well.
  private func startTap() {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
        callback: { _, type, event, info in
          let mode = Unmanaged<HintMode>.fromOpaque(info!).takeUnretainedValue()
          return mode.intercept(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      log("hint mode: event tap refused")
      return exit()
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    self.tap = tap
  }

  private func intercept(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    guard isActive else { return Unmanaged.passUnretained(event) }
    // Cmd chords (Cmd+Tab, Cmd+W) keep their meaning and end hint mode.
    if event.flags.contains(.maskCommand) {
      DispatchQueue.main.async { self.exit() }
      return Unmanaged.passUnretained(event)
    }
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    // Ctrl+; belongs to the Carbon hotkey, which toggles hint mode off.
    if Int(keyCode) == kVK_ANSI_Semicolon, event.flags.contains(.maskControl) {
      return Unmanaged.passUnretained(event)
    }
    if type == .keyDown { DispatchQueue.main.async { self.handle(keyCode) } }
    return nil
  }

  private func handle(_ keyCode: UInt16) {
    guard let view else { return }
    switch Int(keyCode) {
    case kVK_Escape: return exit()
    case kVK_Delete:
      if view.typed.isEmpty { return exit() }
      view.typed.removeLast()
      view.needsDisplay = true
      return
    default: break
    }
    guard let letter = letterForKeyCode[keyCode] else { return }
    if let lines = scrollLines[letter], view.typed.isEmpty { return scroll(lines) }
    guard alphabet.contains(letter) else { return }
    let typed = view.typed + String(letter)
    let matching = targets.keys.filter { $0.hasPrefix(typed) }
    if matching.isEmpty { return }
    if let target = targets[typed] { return activate(target) }
    view.typed = typed
    view.needsDisplay = true
  }

  private let scrollLines: [Character: Int32] = ["j": -3, "k": 3, "d": -15, "u": 15]

  private func scroll(_ lines: Int32) {
    guard let window, let rect = frame(of: window) else { return }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left)?
      .post(tap: .cghidEventTap)
    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?
      .post(tap: .cghidEventTap)
    scheduleRefresh(after: 0.15)
  }

  private func activate(_ target: Target) {
    exit()
    if textRoles.contains(target.role) {
      AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
      return
    }
    if AXUIElementPerformAction(target.element, kAXPressAction as CFString) != .success {
      let point = CGPoint(x: target.rect.midX, y: target.rect.midY)
      for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
          .post(tap: .cghidEventTap)
      }
    }
  }
}

// Ctrl+; through Carbon: no input-monitoring grant, and held only while
// Claude is frontmost so the chord stays free in every other app.
final class Hotkey {
  private var ref: EventHotKeyRef?
  private let action: () -> Void

  init(action: @escaping () -> Void) {
    self.action = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(), { _, _, data in
        Unmanaged<Hotkey>.fromOpaque(data!).takeUnretainedValue().action()
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
  }

  func setEnabled(_ enabled: Bool) {
    if enabled, ref == nil {
      let id = EventHotKeyID(signature: OSType(0x4356_494D), id: 1)
      RegisterEventHotKey(UInt32(kVK_ANSI_Semicolon), UInt32(controlKey), id, GetApplicationEventTarget(), 0, &ref)
    } else if !enabled, let ref {
      UnregisterEventHotKey(ref)
      self.ref = nil
    }
  }
}

// An LSUIElement app has no Dock icon and no menu bar of its own; without this
// item the only way to quit it would be Activity Monitor.
final class StatusMenu: NSObject, NSMenuDelegate {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let hintMode: HintMode
  private let accessibility = NSMenuItem(title: "", action: #selector(openAccessibility), keyEquivalent: "")

  init(hintMode: HintMode) {
    self.hintMode = hintMode
    super.init()
    item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "claude-vimium")
    let menu = NSMenu()
    menu.delegate = self
    let show = NSMenuItem(title: "Show Hints in Claude  (⌃;)", action: #selector(showHints), keyEquivalent: "")
    let quit = NSMenuItem(title: "Quit claude-vimium", action: #selector(quit), keyEquivalent: "q")
    for entry in [show, accessibility, quit] { entry.target = self }
    let about = NSMenuItem(title: "claude-vimium \(appVersion)", action: nil, keyEquivalent: "")
    about.isEnabled = false
    [about, .separator(), show, accessibility, .separator(), quit].forEach(menu.addItem)
    item.menu = menu
  }

  func menuWillOpen(_ menu: NSMenu) {
    accessibility.title = AXIsProcessTrusted() ? "Accessibility: allowed" : "Allow Accessibility…"
  }

  @objc private func showHints() { hintMode.enter() }

  @objc private func openAccessibility() { NSWorkspace.shared.open(accessibilitySettings) }
  @objc private func quit() { NSApp.terminate(nil) }
}

final class URLHandler: NSObject {
  private let hintMode: HintMode
  init(hintMode: HintMode) { self.hintMode = hintMode }

  @objc func handle(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
    guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let command = urlCommand(url)
    else { return }
    if command == .toggle { hintMode.toggle() }
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let me = ProcessInfo.processInfo.processIdentifier
if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
  .contains(where: { $0.processIdentifier != me })
{
  exit(0)
}

let hintMode = HintMode()
// Registered before app.run(), so a URL that launched the app is delivered, not lost.
let urlHandler = URLHandler(hintMode: hintMode)
NSAppleEventManager.shared().setEventHandler(
  urlHandler, andSelector: #selector(URLHandler.handle(_:withReply:)),
  forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
log("started \(appVersion) at \(Bundle.main.bundlePath); accessibility trusted=\(trusted)")
if !trusted {
  Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
    guard AXIsProcessTrusted() else { return }
    log("accessibility trusted=true")
    timer.invalidate()
  }
}

let statusMenu = StatusMenu(hintMode: hintMode)
let hotkey = Hotkey { DispatchQueue.main.async { hintMode.toggle() } }
let isClaudeFront = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID }
hotkey.setEnabled(isClaudeFront())
NSWorkspace.shared.notificationCenter.addObserver(
  forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { _ in
  // The tap swallows every key, so hint mode must not outlive Claude's focus.
  if !isClaudeFront() { hintMode.exit() }
  hotkey.setEnabled(isClaudeFront())
}

app.run()
