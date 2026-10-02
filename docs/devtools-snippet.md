# DevTools snippet

The same hint mode, run from Claude Desktop's DevTools instead of installed. It labels the web page inside the window, not the sidebar or title bar the [app](../README.md) reaches, and it adds a settings and help panel. It needs no permissions.

A DevTools snippet **persists across app restarts**: you save it once and run it in three keystrokes afterwards.

**One-time setup**

1. In Claude Desktop, press `Cmd+Alt+I` to open DevTools
2. Go to **Sources → Snippets → New snippet**
3. Paste the contents of [`src/claude-vimium.js`](../src/claude-vimium.js) and name it `claude-vimium`
4. Press `Cmd+Enter` to run it

**After each app restart**

`Cmd+Alt+I` → Snippets → `Cmd+Enter`.

The script is re-runnable: running it again tears the previous instance down first, so you can never end up with duplicate listeners.

## Keys

| key | action |
|---|---|
| `Ctrl+;` | enter / leave hint mode (configurable) |
| `a s f g q w e r t z x c v` | type a hint label |
| `h` `j` `k` `l` | scroll left / down / up / right |
| `↑` `↓` `←` `→` | same |
| `d` / `u` | half page down / up |
| `Ctrl+d` / `Ctrl+u` | same |
| `Home` / `End` | top / bottom |
| `Backspace` | undo one label character — or leave, if nothing is typed |
| `,` | settings |
| `?` | help, showing your actual bindings |
| `Esc` | leave |

No key ever carries two meanings — `h j k l d u , ?` are reserved for navigation and commands, and the hint alphabet can't contain any of them. That's enforced by validation, not convention: the settings panel refuses any alphabet containing a reserved key.

## Settings

Press `,` while hints are showing. You can change the leader key, the hint alphabet, and the scroll step. Settings persist in `localStorage`.

Two rules the settings panel enforces, both of which exist to keep you from locking yourself out:

- **The leader key needs a modifier** (Ctrl, Alt, or Cmd). A bare letter would fire hint mode every time you typed it, and the settings panel is only reachable *through* hint mode — you would have no way back except clearing `localStorage` by hand. Shift does not count: `Shift+a` is just a capital A to anyone typing.
- **The hint alphabet cannot contain a reserved key** (`h j k l d u , ?`). Those are consumed before label matching, so an element labeled with one could never be clicked.

## Non-latin keyboards

The snippet works on a Korean layout, and the reason is worth knowing if you are building something similar.

On a Korean layout the key printed `a` reports `event.key === 'ㅁ'`, so matching on the logical key can never succeed. This extension prefers the logical key — which keeps Dvorak and AZERTY correct, where the physical key is the wrong answer — and falls back to `event.code` only when the logical key is not a latin letter at all.

There is a second, nastier half. macOS's Korean IME starts composing **even when the keydown is `preventDefault()`ed**, so the first hint keystroke opens a composition and every keystroke after it arrives with `isComposing` set. Guarding on that would swallow them; ignoring it would corrupt real typing. The fix is to remove the thing being composed into: hint mode blurs the focused element on entry and restores focus on exit.

Neither problem is visible to code review. Both were found by a human pressing keys.

## Why the snippet has no installer

Claude Desktop ships a complete local copy of the web app at `Contents/Resources/ion-dist/`, served at `app://localhost` — and it is not what the window renders, so there is still no on-disk document to add a `<script>` tag to. A probe placed in that `index.html` in August 2026 never ran; the top document's origin was `claude.ai`.

What decides it is the deployment mode, and there are exactly two. The first-party one loads remote `claude.ai`; a third-party one loads the bundle. No ordinary sign-in reaches the second — it is selected by a merged config carrying an `inference`, `selfHosted` or `bootstrap.url` key. Checked on 2.2553.1: the only origin in the app's Local Storage is `https://claude.ai`.

You can write that config — its local tier is an ordinary user-writable directory — and you should not. Third-party mode *is* a third-party deployment: the app answers `/api/bootstrap` and friends locally and sends inference to whatever provider the config names, so your claude.ai account stops working. That is a large price for a keyboard shortcut. (In that mode the bundle would not resist injection. Its `index.html` carries no `<meta>` policy and the CSP is synthesized at load time, with `script-src 'self'` admitting a sibling file, an automatic `sha256-` for each inline block, and no SRI.)

Injecting from outside the app is closed off too. The binary is signed with Hardened Runtime and carries none of the entitlements that would allow it — no `get-task-allow`, no `disable-library-validation`, no `allow-dyld-environment-variables` — so debugger attach and `DYLD_INSERT_LIBRARIES` are both out. And the app terminates itself on startup if it sees `--remote-debugging-port` or `--remote-debugging-pipe` — now alongside `--disable-web-security`, `--host-rules` and `--ignore-certificate-errors` — which closes the Chrome DevTools Protocol route.

That leaves patching the app bundle's `app.asar` to add a preload script. It works, but it means recomputing the ASAR integrity hash and editing `Info.plist` — get it wrong and the app will not launch — and redoing it after every app update. Any edit under `Contents/Resources/` also breaks the `_CodeSignature/CodeResources` seal. That does not stop the app launching, but it is a second thing a loader has to own.

The [app](../README.md#how-it-works) sidesteps all of this by working from outside the page, through the Accessibility API, instead of injecting into it.

