// Hint mode for the whole Claude Desktop window, driven through the macOS
// Accessibility API: the web UI and the app chrome both appear in the AX tree,
// which no mod surface reaches. The vimium-hints mod builds and launches this.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

let claudeBundleID = "com.anthropic.claudefordesktop"
let alphabet = Array("asfgqwertzxcv")
let clickableRoles: Set<String> = [
  "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXPopUpButton", "AXCheckBox",
  "AXMenuButton", "AXRadioButton", "AXTab", "AXComboBox", "AXMenuItem", "AXDisclosureTriangle",
]
let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
let clipRoles: Set<String> = ["AXScrollArea", "AXWindow", "AXWebArea"]

// Physical keys on an ANSI board, so a Korean or other non-latin input source
// still types hint letters (see README, "Non-latin keyboards").
let letterForKeyCode: [UInt16: Character] = [
  0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
  12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
  37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
]

// Port of generateLabels in src/claude-vimium.js: shortest labels, none a prefix of another.
func generateLabels(_ count: Int) -> [String] {
  let n = alphabet.count
  let total = min(count, n * n)
  if total <= 0 { return [] }
  if total <= n { return alphabet.prefix(total).map(String.init) }
  let single = max(0, (n * n - total) / (n - 1))
  var labels = alphabet.prefix(single).map(String.init)
  for i in single..<n {
    for j in 0..<n where labels.count < total { labels.append(String([alphabet[i], alphabet[j]])) }
  }
  return labels
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
    if clickableRoles.contains(role), let rect, rect.width > 2, rect.height > 2 {
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
  var isActive: Bool { panel != nil }

  func toggle() { isActive ? exit() : enter() }

  func enter() {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first else { return }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    // Chromium builds its web AX tree only once an assistive client asks.
    AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    guard let window = (attr(root, kAXFocusedWindowAttribute) as! AXUIElement?)
      ?? (attr(root, kAXWindowsAttribute) as? [AXUIElement])?.first,
      let windowRect = frame(of: window)
    else { return }
    self.window = window
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
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      self.tap = nil
    }
  }

  // An active (filtering) tap needs only the Accessibility grant the helper
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
      FileHandle.standardError.write("ClaudeVimium: event tap refused\n".data(using: .utf8)!)
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
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self, self.isActive, let window = self.window, let rect = frame(of: window) else { return }
      self.show(windowRect: rect, found: collectTargets(in: window))
    }
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let me = ProcessInfo.processInfo.processIdentifier
if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
  .contains(where: { $0.processIdentifier != me })
{
  exit(0)
}

let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
FileHandle.standardError.write("ClaudeVimium: accessibility trusted=\(trusted)\n".data(using: .utf8)!)

let hintMode = HintMode()
let hotkey = Hotkey { DispatchQueue.main.async { hintMode.toggle() } }
let isClaudeFront = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID }
hotkey.setEnabled(isClaudeFront())
NSWorkspace.shared.notificationCenter.addObserver(
  forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { _ in
  hotkey.setEnabled(isClaudeFront() || hintMode.isActive)
}

// The mod's /vimium sends SIGUSR1: Desktop panes do not take hotkeys.
signal(SIGUSR1, SIG_IGN)
let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
usr1.setEventHandler { hintMode.toggle() }
usr1.resume()

app.run()
