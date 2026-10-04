// Run with `make test`: compiles app/Hints.swift with this file.
import Foundation

func check(_ ok: Bool, _ what: String, line: Int = #line) {
  if !ok {
    print("FAIL line \(line): \(what)")
    exit(1)
  }
}

let small = Array("abcd")
check(generateLabels(3, alphabet: small) == ["a", "b", "c"], "single letters when they fit")
let six = generateLabels(6, alphabet: small)
check(six.count == 6 && Set(six).count == 6, "six unique labels")
check(six.allSatisfy { a in six.allSatisfy { b in a == b || !b.hasPrefix(a) } }, "prefix-free")
check(generateLabels(500).count == alphabet.count * alphabet.count, "capped at two letters")
check(generateLabels(0).isEmpty, "no labels for no targets")

check(isHintable(role: "AXButton", subrole: nil), "plain button")
check(!isHintable(role: "AXButton", subrole: "AXCloseButton"), "close button excluded")
check(!isHintable(role: "AXButton", subrole: "AXMinimizeButton"), "minimize button excluded")
check(!isHintable(role: "AXButton", subrole: "AXFullScreenButton"), "full screen button excluded")
check(!isHintable(role: "AXGroup", subrole: nil), "non-clickable role")

check(urlCommand("hintvim://toggle") == .toggle, "toggle")
check(urlCommand("HINTVIM://Toggle/") == .toggle, "case and trailing slash")
check(urlCommand("hintvim://") == .start, "bare scheme starts")
check(urlCommand("hintvim://start") == .start, "start")
check(urlCommand("hintvim://probe") == .probe, "probe")
check(urlCommand("hintvim://rm-rf") == nil, "unknown command ignored")
check(urlCommand("https://toggle") == nil, "other scheme ignored")

print("hints OK")
