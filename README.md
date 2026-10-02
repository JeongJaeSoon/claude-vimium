# claude-vimium

Keyboard navigation for Claude Desktop, in the spirit of [Vimium](https://vimium.github.io/).

Press a leader key and every clickable thing on screen gets a short label. Type the label, that element activates. No mouse.

```
Ctrl+;            →  labels appear on every button, link, and input
type "sf"         →  that element is clicked
j / k / d / u     →  scroll while the labels stay live
,  /  ?           →  settings  /  help
Esc               →  leave
```

## Why this exists

Claude Desktop ships plenty of shortcuts — `Cmd+K`, `Cmd+1…9`, `Cmd+Shift+F` — but anything without a binding needs the mouse: the working-directory pill, the model and mode menus, per-message action buttons. Hint mode covers all of it at once, without inventing a shortcut per control.

## Install

There is no installer, and that is not an oversight. See [Why there is no installer](#why-there-is-no-installer).

The extension runs from a DevTools snippet, which **persists across app restarts** — you save it once and run it in three keystrokes afterwards.

**One-time setup**

1. In Claude Desktop, press `Cmd+Alt+I` to open DevTools
2. Go to **Sources → Snippets → New snippet**
3. Paste the contents of [`src/claude-vimium.js`](src/claude-vimium.js) and name it `claude-vimium`
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

Works on a Korean layout, and the reason is worth knowing if you are building something similar.

On a Korean layout the key printed `a` reports `event.key === 'ㅁ'`, so matching on the logical key can never succeed. This extension prefers the logical key — which keeps Dvorak and AZERTY correct, where the physical key is the wrong answer — and falls back to `event.code` only when the logical key is not a latin letter at all.

There is a second, nastier half. macOS's Korean IME starts composing **even when the keydown is `preventDefault()`ed**, so the first hint keystroke opens a composition and every keystroke after it arrives with `isComposing` set. Guarding on that would swallow them; ignoring it would corrupt real typing. The fix is to remove the thing being composed into: hint mode blurs the focused element on entry and restores focus on exit.

Neither problem is visible to code review. Both were found by a human pressing keys.

## Why there is no installer

Claude Desktop ships a complete local copy of the web app at `Contents/Resources/ion-dist/`, served at `app://localhost` — and it is not what the window renders, so there is still no on-disk document to add a `<script>` tag to. A probe placed in that `index.html` in August 2026 never ran; the top document's origin was `claude.ai`.

What decides it is the deployment mode, and there are exactly two. The first-party one loads remote `claude.ai`; a third-party one loads the bundle. No ordinary sign-in reaches the second — it is selected by a merged config carrying an `inference`, `selfHosted` or `bootstrap.url` key. Checked on 2.2553.1: the only origin in the app's Local Storage is `https://claude.ai`.

You can write that config — its local tier is an ordinary user-writable directory — and you should not. Third-party mode *is* a third-party deployment: the app answers `/api/bootstrap` and friends locally and sends inference to whatever provider the config names, so your claude.ai account stops working. That is a large price for a keyboard shortcut. (In that mode the bundle would not resist injection. Its `index.html` carries no `<meta>` policy and the CSP is synthesized at load time, with `script-src 'self'` admitting a sibling file, an automatic `sha256-` for each inline block, and no SRI.)

Injecting from outside the app is closed off too. The binary is signed with Hardened Runtime and carries none of the entitlements that would allow it — no `get-task-allow`, no `disable-library-validation`, no `allow-dyld-environment-variables` — so debugger attach and `DYLD_INSERT_LIBRARIES` are both out. And the app terminates itself on startup if it sees `--remote-debugging-port` or `--remote-debugging-pipe` — now alongside `--disable-web-security`, `--host-rules` and `--ignore-certificate-errors` — which closes the Chrome DevTools Protocol route.

That leaves patching the app bundle's `app.asar` to add a preload script. It works, but it means recomputing the ASAR integrity hash and editing `Info.plist` — get it wrong and the app will not launch — and redoing it after every app update. Any edit under `Contents/Resources/` also breaks the `_CodeSignature/CodeResources` seal. That does not stop the app launching, but it is a second thing a loader has to own.

That belongs in a dedicated tool rather than in each extension. Automatic loading is planned via a separate loader project; until then, the snippet is the supported path.

## Why not a Claude Code mod

Claude Code's mods — plugins whose behaviour is a TypeScript `register(on, options)` module wrapping engine events — draw on four surfaces from one codebase (`terminal`, `desktop`, `mobile`, `vscode`) and install with a single `claude plugin install`. That sounds like exactly the installer this project lacks, so it is worth saying why it is not the answer.

A mod hooks the Claude Code engine, not the window. Its nouns reach sessions, tools, commands, config and the engine's own render sites; none of them reach the app's chrome, which is where the working-directory pill and the model and mode menus live. Hint mode would have nothing to label.

The keyboard is closed too. There is no global key hook. A `Button` may carry a `hotkey`, but it is one lowercase letter or digit and only while that plugin's own site holds the focus; `action` binds to a keybinding the engine already has, and an unknown name is refused, so `Ctrl+;` cannot be registered at all. Only two sites keep a focus ring — a `Pane`, and the band above the prompt.

So a mod is not a port of this extension. It is a different, smaller thing on a different layer — and `plugin/` is that thing.

### The smaller thing: `vimium-hints`

`/vimium` in a Claude Code session opens a pane of six actions, each labeled with a letter from the hint alphabet: copy the last reply, the last code block, the working directory or the session id; show context usage; compact.

```bash
claude plugin marketplace add <path to this repo>
claude plugin install vimium-hints@vimium-hints
sh scripts/enable-mods.sh     # --off to undo
```

The last line is not optional on every account. Mods are early access: the engine loads a plugin's hooks module only when `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` is set or the rollout flag `tengu_plugin_hooks_modules` serves on, and the flag defaults off. The script sets the variable in `~/.claude/settings.json`, which the Desktop Code tab reads too.

Checked in Claude Desktop 2.16120.0 (Claude Code 2.1.284), October 2026:

- Without the variable, `/vimium` answers "isn't a command here" — the plugin is loaded, its module is not.
- With it, `/vimium` opens the pane beside the transcript, and clicking an action runs it: the clipboard held the working directory and the toast read `vimium-hints: Copied working directory`.
- The hint letters do not work there. Clicking the pane does not give it the keyboard, Tab stays inside the composer, and the letter lands in the prompt — as `ㄹ` on a Korean layout. In the Desktop pane, the letters are labels and nothing more.
- Desktop's own composer still prints "/vimium isn't a command here." under the prompt, because it only knows built-in commands; the engine runs the command anyway.

## Limitations

- macOS only. Verified on Korean and English layouts; other platforms untested.
- The DOM layer has no automated tests. Overlay rendering, key dispatch, and focus handling are verified by hand — a deliberate trade, since a DOM harness would mean a build step and dependencies that this project does not have.
- Element discovery deliberately avoids class names (the app's are hashed and change every release) but still depends on roles and layout, so a large UI redesign could require adjustment.

## Development

No dependencies, no build step. The extension is one file; pure logic is exported behind a `typeof module` guard so Node can test it.

```bash
node test/labels.test.js
node test/filters.test.js
node test/config.test.js
```

Iterate by pasting `src/claude-vimium.js` into the DevTools console — it tears down the previous instance on each run.

`docs/superpowers/` holds the design spec, the implementation plan, the manual verification checklists, and the notes behind the two sections above.

## License

MIT
