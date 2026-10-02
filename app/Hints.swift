// Pure logic shared by the app and test/hints/main.swift: no AppKit, no AX.

let alphabet = Array("asfgqwertzxcv")

let clickableRoles: Set<String> = [
  "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXPopUpButton", "AXCheckBox",
  "AXMenuButton", "AXRadioButton", "AXTab", "AXComboBox", "AXMenuItem", "AXDisclosureTriangle",
]
let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
let clipRoles: Set<String> = ["AXScrollArea", "AXWindow", "AXWebArea"]

// A one-letter label on the close button turns a typo into a closed window.
let windowControlSubroles: Set<String> = [
  "AXCloseButton", "AXMinimizeButton", "AXFullScreenButton", "AXZoomButton",
]

func isHintable(role: String, subrole: String?) -> Bool {
  clickableRoles.contains(role) && !windowControlSubroles.contains(subrole ?? "")
}

// Physical keys on an ANSI board, so a Korean or other non-latin input source
// still types hint letters (see README, "Non-latin keyboards").
let letterForKeyCode: [UInt16: Character] = [
  0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
  12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
  37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
]

// Port of generateLabels in src/claude-vimium.js: shortest labels, none a prefix of another.
func generateLabels(_ count: Int, alphabet: [Character] = alphabet) -> [String] {
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

enum URLCommand: Equatable {
  case start, toggle, probe
}

// claude-vimium://toggle from /vimium; a bare claude-vimium:// only launches the app;
// probe logs what hint mode would label, for `claude-vimium doctor`.
func urlCommand(_ url: String) -> URLCommand? {
  let prefix = "claude-vimium://"
  guard url.lowercased().hasPrefix(prefix) else { return nil }
  var rest = url.dropFirst(prefix.count).lowercased()
  if rest.hasSuffix("/") { rest.removeLast() }
  switch rest {
  case "", "start": return .start
  case "toggle": return .toggle
  case "probe": return .probe
  default: return nil
  }
}

