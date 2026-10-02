# claude-vimium

Keyboard navigation for Claude Desktop, in the spirit of [Vimium](https://vimium.github.io/).

Press a leader key and every clickable thing on screen gets a short label. Type the label, that element activates. No mouse.

```
Ctrl+;            →  labels appear on every button, link, and input
type "sf"         →  that element is clicked
j / k / d / u     →  scroll
Esc               →  leave
```

## Why this exists

Claude Desktop ships plenty of shortcuts — `Cmd+K`, `Cmd+1…9`, `Cmd+Shift+F` — but anything without a binding needs the mouse: the working-directory pill, the model and mode menus, per-message action buttons. Hint mode covers all of it at once, without inventing a shortcut per control.

## Two ways to run it

| | **Plugin** (recommended) | **DevTools snippet** |
|---|---|---|
| How you install it | `claude plugin install`, once | Paste a script into DevTools |
| After an app restart | Nothing to do | Run the snippet again (three keys) |
| What gets labels | The whole window, sidebar and title bar included | The web page inside the window |
| Settings and help panel | No | Yes (`,` and `?`) |
| Needs | macOS, Claude Code mods, Xcode Command Line Tools, the Accessibility permission | Nothing |

The plugin is a [Claude Code mod](https://code.claude.com/docs/en/plugins/mods/overview) that starts a small native macOS helper. [How the plugin works](#how-the-plugin-works) explains why it needs one.

## Plugin

### Before you start

- **macOS** with **Claude Desktop**, used from its **Code** tab in a **Local** session. The helper has to run on your Mac, and only a Local session runs the mod there.
- **Xcode Command Line Tools**, because the helper is compiled on your Mac the first time it runs. Check with `xcrun --find swiftc`. If that fails, run `xcode-select --install`.
- **Claude Code mods turned on.** See the next step.

### 1. Make sure mods can load

Mods are [on by default from Claude Code v2.1.287](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off). Claude Desktop runs its own bundled copy of Claude Code, which can be older than the `claude` in your terminal. The folder names here are the versions it has:

```bash
ls ~/Library/Application\ Support/Claude/claude-code/
```

- **2.1.287 or later:** nothing to do.
- **Older:** turn the early-access switch on. The script below adds `"CLAUDE_CODE_ENABLE_FUNCTION_HOOKS": "1"` to `env` in `~/.claude/settings.json`, and writes a backup first. It needs `jq`. Remove the switch again with `--off` once Desktop is on 2.1.287 or later. The docs ask for that, because from that version the variable is ignored.

  ```bash
  git clone https://github.com/JeongJaeSoon/claude-vimium.git
  sh claude-vimium/scripts/enable-mods.sh
  ```

  If you would rather not run a script, add the key to `~/.claude/settings.json` by hand:

  ```json
  { "env": { "CLAUDE_CODE_ENABLE_FUNCTION_HOOKS": "1" } }
  ```

To confirm that mods can load, run `claude plugin test` in an empty directory. `no hooks module to load` means they can. Any other message is explained in [Check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load).

### 2. Install

```bash
claude plugin marketplace add JeongJaeSoon/claude-vimium
claude plugin install vimium-hints@vimium-hints
```

Desktop's **+ → Plugins → Add plugin** works too, once the marketplace is added. A plugin installed at user scope is shared by the terminal and Desktop's local sessions.

> [!WARNING]
> A mod runs with your permissions, and this one also builds and starts a program that controls Claude Desktop through the Accessibility API. Read [`plugin/hooks/register.tsx`](plugin/hooks/register.tsx) and [`plugin/helper/ClaudeVimium.swift`](plugin/helper/ClaudeVimium.swift) before you install. `claude plugin validate plugin` lists every event the mod hooks and every call it makes.

### 3. Start a session and allow Accessibility

Open a new **Local** session in Desktop's Code tab. When the session starts, the mod:

1. builds the helper into `~/Library/Application Support/claude-vimium/ClaudeVimium.app` (first run only, a few seconds),
2. starts it in the background, and
3. shows the toast `vimium-hints: Ctrl+; for hints`.

macOS then asks you to let **ClaudeVimium** control your computer. Open **System Settings → Privacy & Security → Accessibility** and turn it on.

### 4. Use it

Click into the Claude window and press `Ctrl+;`.

| Key | Action |
|---|---|
| `Ctrl+;` | Show or hide the labels. Works only while Claude is the frontmost app. |
| `a s f g q w e r t z x c v` | Type a label. The element is pressed, or focused if it's a text field. |
| `j` / `k` | Scroll down / up a little, then relabel |
| `d` / `u` | Scroll down / up half a page, then relabel |
| `Delete` | Undo one typed letter, or leave if nothing is typed |
| `Esc` | Leave |
| `Cmd` + anything | Leave, and the shortcut still works (`Cmd+Tab`, `Cmd+W`) |

While labels are showing, keys go to the helper and never reach Claude, so nothing leaks into the prompt. Letters are read by physical position on a US (ANSI) layout, so the labels work with a Korean input source on, and with Dvorak or AZERTY you type the key in the QWERTY position.

Two slash commands come with it:

- `/vimium` shows the labels, the same as `Ctrl+;`. If the helper isn't running, it starts it instead and replies `helper started`; press `Ctrl+;` then.
- `/vimium-palette` opens a pane of six actions: copy the last reply, the last code block, the working directory, or the session id; show context usage; compact. In Desktop you click them. Their letter hotkeys only work in the terminal.

Desktop's prompt box prints `/vimium isn't a command here.` under either command because it only knows built-in commands. The command still runs.

### Update

```bash
claude plugin marketplace update vimium-hints
claude plugin update vimium-hints@vimium-hints
```

Then start a new session. When an update changes the helper's source, the helper is rebuilt, and **macOS treats the rebuilt helper as a new app**. The old Accessibility entry no longer applies, even though it still shows as on. Remove **ClaudeVimium** with **−** in the Accessibility list, then allow the new one when asked. The helper is signed locally (ad hoc) rather than with a Developer ID, so this happens once per helper change.

### Uninstall

```bash
pkill -x ClaudeVimium
claude plugin uninstall vimium-hints@vimium-hints
claude plugin marketplace remove vimium-hints
rm -rf ~/Library/Application\ Support/claude-vimium
```

Then remove **ClaudeVimium** from **System Settings → Privacy & Security → Accessibility**. If you turned on the mods switch only for this, undo it with `sh scripts/enable-mods.sh --off`.

### Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Ctrl+;` shows nothing | **Claude must be the frontmost app.** If an input method is composing in the prompt box (an underlined character or a candidate list), press `Esc` to cancel it first. If labels still don't appear, the Accessibility permission doesn't match the current build. Remove and re-add it as in [Update](#update), then restart the helper (next row). |
| Restart the helper | `pkill -x ClaudeVimium`, then run `/vimium` in a session or start a new one. |
| Toast says `vimium-hints: helper failed: …` | Usually `swiftc` is missing. Install the Command Line Tools and start a new session. |
| No toast and no `/vimium` | The mod didn't load. Check [step 1](#1-make-sure-mods-can-load), then [Troubleshoot a mod](https://code.claude.com/docs/en/plugins/mods/troubleshoot). |
| Labels sit in the wrong place after resizing | Press `Esc` and `Ctrl+;` again. Labels are measured when they appear. |

### Good to know

- **It also starts from the terminal.** The mod loads in every Claude Code session, so running `claude` in a terminal starts the helper too. `Ctrl+;` is only claimed while Claude Desktop is frontmost, so other apps keep the chord.
- **The helper outlives Desktop.** It keeps running after you quit Claude and stops at logout. It has no login item. The next session starts it again.

## How the plugin works

```
Claude Desktop  ──session.start──▶  mod (plugin/hooks/register.tsx)
                                      │  $.process.run
                                      ▼
                                    helper/launch.sh  ──builds once──▶  ClaudeVimium.app
                                                                        │
           Ctrl+;  ─────────────────────────────────────────────────────┤ Accessibility API
                                                                        ▼
                                                     labels over the whole Claude window
```

A mod alone cannot do hint mode. Mods hook the Claude Code engine, not the window: their render sites are the engine's own (panes, the band above the prompt, tool rows), so the app's sidebar and title bar are out of reach. A mod can't register a global key either. A `Button` hotkey is one letter, and only while that mod's own pane has the focus. In Desktop, clicking a mod's pane doesn't take the keyboard away from the prompt box. A `Client` element runs in an iframe that can't see the page around it.

macOS's Accessibility API can see the window. Asked through `AXManualAccessibility`, Chromium exposes the full tree of Claude's window, web content and chrome alike, and `AXPress` fires the same handlers a click would. So the mod's job is installation and startup, and the helper does the labelling:

- **`plugin/hooks/register.tsx`** registers `/vimium` and `/vimium-palette`, and runs `launch.sh` on `session.start`.
- **`plugin/helper/launch.sh`** compiles the helper only when its source hash changes, because every rebuild costs the user an Accessibility re-grant. Then it starts the helper, or signals it (`SIGUSR1`) for `/vimium`.
- **`plugin/helper/ClaudeVimium.swift`** is a menu-bar-less app with these parts:
  - a Carbon hotkey for `Ctrl+;`, held only while Claude is frontmost
  - an Accessibility walk that collects clickable roles, clipped to visible scroll areas
  - a transparent panel that draws the labels
  - an event tap that takes the keys while labels show

The helper is compiled on your machine rather than shipped as a binary. A downloaded unsigned binary would be stopped by Gatekeeper. The cost is the Command Line Tools requirement and the re-grant on helper changes.

## DevTools snippet

No plugin, no permissions: the extension runs from a DevTools snippet, which **persists across app restarts**. You save it once and run it in three keystrokes afterwards. It labels the web page inside the window, not the window's own chrome.

**One-time setup**

1. In Claude Desktop, press `Cmd+Alt+I` to open DevTools
2. Go to **Sources → Snippets → New snippet**
3. Paste the contents of [`src/claude-vimium.js`](src/claude-vimium.js) and name it `claude-vimium`
4. Press `Cmd+Enter` to run it

**After each app restart**

`Cmd+Alt+I` → Snippets → `Cmd+Enter`.

The script is re-runnable: running it again tears the previous instance down first, so you can never end up with duplicate listeners.

### Keys

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

### Settings

Press `,` while hints are showing. You can change the leader key, the hint alphabet, and the scroll step. Settings persist in `localStorage`.

Two rules the settings panel enforces, both of which exist to keep you from locking yourself out:

- **The leader key needs a modifier** (Ctrl, Alt, or Cmd). A bare letter would fire hint mode every time you typed it, and the settings panel is only reachable *through* hint mode — you would have no way back except clearing `localStorage` by hand. Shift does not count: `Shift+a` is just a capital A to anyone typing.
- **The hint alphabet cannot contain a reserved key** (`h j k l d u , ?`). Those are consumed before label matching, so an element labeled with one could never be clicked.

### Non-latin keyboards

Works on a Korean layout, and the reason is worth knowing if you are building something similar.

On a Korean layout the key printed `a` reports `event.key === 'ㅁ'`, so matching on the logical key can never succeed. This extension prefers the logical key — which keeps Dvorak and AZERTY correct, where the physical key is the wrong answer — and falls back to `event.code` only when the logical key is not a latin letter at all.

There is a second, nastier half. macOS's Korean IME starts composing **even when the keydown is `preventDefault()`ed**, so the first hint keystroke opens a composition and every keystroke after it arrives with `isComposing` set. Guarding on that would swallow them; ignoring it would corrupt real typing. The fix is to remove the thing being composed into: hint mode blurs the focused element on entry and restores focus on exit.

Neither problem is visible to code review. Both were found by a human pressing keys.

### Why the snippet has no installer

Claude Desktop ships a complete local copy of the web app at `Contents/Resources/ion-dist/`, served at `app://localhost` — and it is not what the window renders, so there is still no on-disk document to add a `<script>` tag to. A probe placed in that `index.html` in August 2026 never ran; the top document's origin was `claude.ai`.

What decides it is the deployment mode, and there are exactly two. The first-party one loads remote `claude.ai`; a third-party one loads the bundle. No ordinary sign-in reaches the second — it is selected by a merged config carrying an `inference`, `selfHosted` or `bootstrap.url` key. Checked on 2.2553.1: the only origin in the app's Local Storage is `https://claude.ai`.

You can write that config — its local tier is an ordinary user-writable directory — and you should not. Third-party mode *is* a third-party deployment: the app answers `/api/bootstrap` and friends locally and sends inference to whatever provider the config names, so your claude.ai account stops working. That is a large price for a keyboard shortcut. (In that mode the bundle would not resist injection. Its `index.html` carries no `<meta>` policy and the CSP is synthesized at load time, with `script-src 'self'` admitting a sibling file, an automatic `sha256-` for each inline block, and no SRI.)

Injecting from outside the app is closed off too. The binary is signed with Hardened Runtime and carries none of the entitlements that would allow it — no `get-task-allow`, no `disable-library-validation`, no `allow-dyld-environment-variables` — so debugger attach and `DYLD_INSERT_LIBRARIES` are both out. And the app terminates itself on startup if it sees `--remote-debugging-port` or `--remote-debugging-pipe` — now alongside `--disable-web-security`, `--host-rules` and `--ignore-certificate-errors` — which closes the Chrome DevTools Protocol route.

That leaves patching the app bundle's `app.asar` to add a preload script. It works, but it means recomputing the ASAR integrity hash and editing `Info.plist` — get it wrong and the app will not launch — and redoing it after every app update. Any edit under `Contents/Resources/` also breaks the `_CodeSignature/CodeResources` seal. That does not stop the app launching, but it is a second thing a loader has to own.

The plugin sidesteps all of this by working from outside the page, through the Accessibility API, instead of injecting into it.

## Limitations

- macOS only. Verified on Korean and English input sources; other platforms untested.
- The plugin's labels are measured when they appear. Resizing the window or zooming the page while they show doesn't move them.
- The plugin has no settings or help panel yet; the leader key and alphabet are fixed.
- The plugin labels the window's close, minimize, and full-screen buttons too, and the close button often gets a one-letter label (`a`). A stray key can close the window. Claude keeps running; reopen the window from the Dock.
- The DOM layer of the snippet and the helper's drawing have no automated tests. Overlay rendering, key dispatch, and focus handling are verified by hand.
- Element discovery avoids class names (the app's are hashed and change every release) but still depends on roles and layout, so a large UI redesign could require adjustment.

## Development

**Snippet.** No dependencies, no build step. The extension is one file; pure logic is exported behind a `typeof module` guard so Node can test it.

```bash
node test/labels.test.js
node test/filters.test.js
node test/config.test.js
```

Iterate by pasting `src/claude-vimium.js` into the DevTools console — it tears down the previous instance on each run.

**Plugin.**

```bash
claude plugin validate plugin          # what the mod hooks and calls
claude plugin test plugin              # register.test.tsx
swiftc -O plugin/helper/ClaudeVimium.swift -o /tmp/ClaudeVimium   # type-check the helper
```

An installed plugin runs from its cached copy, so edits in this repository don't reach Desktop until you run `claude plugin marketplace update vimium-hints` and `claude plugin update vimium-hints@vimium-hints`. To try a helper change without reinstalling, run `sh plugin/helper/launch.sh` from the repository. That rebuilds the helper, so re-grant Accessibility.

`docs/superpowers/` holds the design spec, the implementation plan, the manual verification checklists, and the notes behind the snippet sections above.

## License

MIT
