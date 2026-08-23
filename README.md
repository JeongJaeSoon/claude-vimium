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

Hint characters are left-hand only and navigation is right-hand, so no key ever carries two meanings. That split is enforced by validation, not convention: the settings panel refuses any alphabet containing a reserved key.

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

Claude Desktop renders **remote `claude.ai`**, not a local bundle. There is no HTML file on disk to add a `<script>` tag to.

Injecting from outside the app is closed off too. The binary is signed with Hardened Runtime and carries none of the entitlements that would allow it — no `get-task-allow`, no `disable-library-validation`, no `allow-dyld-environment-variables` — so debugger attach and `DYLD_INSERT_LIBRARIES` are both out. And the app terminates itself on startup if it sees `--remote-debugging-port` or `--remote-debugging-pipe`, which closes the Chrome DevTools Protocol route.

That leaves patching the app bundle's `app.asar` to add a preload script. It works, but it means recomputing the ASAR integrity hash and editing `Info.plist` — get it wrong and the app will not launch — and redoing it after every app update.

That belongs in a dedicated tool rather than in each extension. Automatic loading is planned via a separate loader project; until then, the snippet is the supported path.

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

`docs/superpowers/` holds the design spec, the implementation plan, and the manual verification checklists.

## License

MIT
