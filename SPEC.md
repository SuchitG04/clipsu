# Succlippy — Clipboard Manager Spec

A native macOS clipboard history manager. Raycast-clipboard-quality, Spotlight-aesthetic, minimal and elegant. Built for personal use.

---

## 1. Goals & non-goals

**Goals**
- Capture everything copied (text, rich text, images, files/links) into a long, searchable history.
- Open instantly via a configurable global hotkey, paste back with one keystroke.
- Keyboard-first, Raycast-style two-pane UI with an actions menu.
- Search across text *and* text recognized inside images (OCR).
- Look and feel like a first-party macOS app: vibrancy, rounded corners, SF Symbols, system accent.

**Non-goals (v1)**
- iCloud / cross-device sync.
- App Store distribution / sandboxing (personal use; runs unsandboxed for full clipboard + accessibility access).
- Snippets / templates / clipboard "stacks" (possible later).
- Windows/Linux.

---

## 2. Tech stack (recommended)

| Concern | Choice | Why |
|---|---|---|
| Language | Swift 5.9+ | Native, fast, full system access |
| UI | SwiftUI + AppKit | SwiftUI for views; AppKit `NSPanel` for the floating non-activating window SwiftUI can't do alone |
| Min OS | macOS 14 (Sonoma) | Latest SwiftUI + Vision OCR APIs |
| App type | Menu bar agent (`LSUIElement = true`) | No Dock icon, lives in the menu bar |
| Storage | SQLite via **GRDB.swift** + **FTS5** | Robust for long history + fast full-text search; images stored on disk, not in the DB |
| OCR | **Vision** (`VNRecognizeTextRequest`) | Free, on-device, no network |
| Global hotkey | **sindresorhus/KeyboardShortcuts** | Includes a recorder UI for configurable shortcuts |
| Launch at login | **sindresorhus/LaunchAtLogin** | One-liner login item |
| Paste-back | `CGEvent` synthetic ⌘V | Requires Accessibility permission |

All third-party deps via Swift Package Manager. No Electron, no web stack — native is the only way to get the aesthetic + OCR + hotkeys cleanly.

---

## 3. Architecture

```
Succlippy (menu bar agent)
├── ClipboardMonitor      polls NSPasteboard.changeCount (~0.4s), reads new contents
├── CaptureService        builds ClipboardItem, dedup, privacy filters, persists
├── OCRService            async Vision OCR on image items → ocrText
├── Store (GRDB)          SQLite + FTS5; CRUD, search, retention pruning
├── ImageStore            writes full image + thumbnail to disk
├── HotKeyManager         KeyboardShortcuts → toggles main panel
├── PasteService          copies item to pasteboard + synthesizes ⌘V to frontmost app
├── UI
│   ├── MainPanel (NSPanel, non-activating, vibrant)
│   │   ├── SearchBar
│   │   ├── ItemList (left)         virtualized, type filter chips
│   │   ├── PreviewPane (right)     full content + metadata
│   │   ├── ActionsMenu (⌘K)        contextual actions
│   │   └── FooterBar               ↵ Paste · ⌘K Actions hints
│   └── SettingsWindow
└── MenuBarItem            quick toggle + Settings + Quit
```

### Clipboard monitoring
macOS gives no clipboard-change notification. Poll `NSPasteboard.general.changeCount` on a timer (~0.4s). On change, read the new contents. Negligible CPU.

### Window behavior
- `NSPanel` with `.nonactivatingPanel` + `.floating` level so the **previously focused app keeps focus** (critical for paste-back).
- Appears centered on the active screen (configurable: center / under cursor / last position).
- `Esc` or click-outside dismisses. `⌘,` opens Settings.
- Opening the panel resets search and selects the most recent item.

---

## 4. Data model

`ClipboardItem`
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `kind` | enum | `text` · `richText` · `image` · `file` · `link` · `color` |
| `plainText` | String? | preview/searchable text for text & links |
| `richData` | Blob? | RTF/HTML data when present (paste preserves formatting) |
| `ocrText` | String? | recognized text for images |
| `imagePath` | String? | full image on disk |
| `thumbPath` | String? | cached thumbnail |
| `imageWidth/Height` | Int? | |
| `fileURLs` | [String]? | for file copies |
| `sourceBundleID` | String? | frontmost app at copy time |
| `sourceAppName` | String? | |
| `contentHash` | String | dedup key (sha256 of canonical content) |
| `byteSize` | Int | |
| `pinned` | Bool | pinned items never auto-expire |
| `copyCount` | Int | times re-used |
| `createdAt` | Date | |
| `lastUsedAt` | Date | |

**FTS5 virtual table** indexes `plainText + ocrText + sourceAppName` for instant search.

**Storage locations**
- DB: `~/Library/Application Support/Succlippy/db.sqlite`
- Images: `~/Library/Application Support/Succlippy/images/{id}.png`
- Thumbs: `~/Library/Application Support/Succlippy/thumbs/{id}.jpg`

---

## 5. Capture rules

- **Dedup:** if `contentHash` matches the most recent item (or any existing item, configurable), bump `lastUsedAt` + `copyCount` instead of inserting a duplicate; re-order to top.
- **Multi-type pasteboards:** store the richest representation; derive `plainText` preview. Keep RTF/HTML so formatted paste works; offer "Paste as plain text" separately.
- **Links:** if `plainText` is a valid URL, mark `kind = link` → enables "Open in browser".
- **Files:** `NSFilenamesPboardType` → store paths, show file icon + name.
- **Images:** persist to disk, generate thumbnail, queue OCR. Skip OCR for images above a size threshold (configurable) but still store them.
- **Color:** detect hex/`NSColor` copies → swatch preview (nice-to-have).
- **Size cap:** items above a configurable byte limit (default 50 MB) are skipped with a quiet log.

### Privacy filters (important)
- Skip pasteboards marked `org.nspasteboard.TransientType` or `org.nspasteboard.ConcealedType` (password managers like 1Password set these) — never store passwords.
- User-configurable **app exclusion list** (don't capture from these bundle IDs).
- Everything is **local only**; no network calls ever.
- Optional: pause capture (menu bar toggle "Pause Succlippy").

---

## 6. Search

- Live filter as you type (debounced ~80ms).
- Matches `plainText`, `ocrText`, and `sourceAppName` via FTS5 (prefix + token matching).
- Type filter chips above the list: **All · Text · Links · Images · Files · Pinned**.
- Results ranked: pinned first (when in All), then recency, with exact/prefix matches boosted.
- Empty-search state shows full history, newest first.

---

## 7. Actions (the ⌘K menu)

Triggered by `⌘K` or right-click on an item. Contextual to item kind:

| Action | Shortcut | Applies to |
|---|---|---|
| Paste | `↵` | all |
| Paste as plain text | `⌘↵` | text/rich |
| Copy to clipboard | `⌘C` | all |
| Edit | `⌘E` | text/rich (inline editor, saves a new edited entry) |
| Pin / Unpin | `⌘P` | all |
| Open in browser | `⌘O` | links |
| Open image | `↵`/`⌘O` | images (Quick Look or default app) |
| Quick Look | `Space` | all |
| Save image to file… | `⌘S` | images |
| Copy OCR text | — | images with `ocrText` |
| Reveal source app | — | all with source |
| Delete | `⌘⌫` | all |
| Clear all history… | — | global (confirm) |

`↵` **always pastes** the selected item into the previously focused app (default). Open/Quick Look for images stay on `Space` / `⌘O`. Configurable to "smart per type" in Settings.

---

## 8. Paste-back flow

1. User selects item, presses `↵`.
2. Panel closes (focus returns to prior app).
3. `PasteService` writes item to `NSPasteboard.general`.
4. Synthesize `⌘V` via `CGEvent` to the now-frontmost app.
5. Bump `copyCount` + `lastUsedAt`.

Requires **Accessibility** permission (prompt + guided deep-link to System Settings on first run). Fallback if denied: item is placed on the clipboard and a toast says "Copied — press ⌘V to paste."

---

## 9. UI / aesthetic

Raycast-style two-pane, Spotlight-grade polish.

```
┌───────────────────────────────────────────────────────────┐
│  🔍  Search clipboard…                                       │  ← search bar
├──────────────┬────────────────────────────────────────────┤
│ All Text Img │                                            │  ← filter chips
│ Links Files  │            PREVIEW                          │
│ ───────────  │   full content / image render              │
│ ▸ entry 1    │                                            │
│ ▸ entry 2    │   ── metadata ──                           │
│ ▸ entry 3    │   Type · Source app (icon) · Date          │
│   …          │   Size · Dimensions · Copied N times       │
├──────────────┴────────────────────────────────────────────┤
│  ↵ Paste        ⌘C Copy        ⌘K Actions                  │  ← footer
└───────────────────────────────────────────────────────────┘
```

- **Background:** `NSVisualEffectView` `.hudWindow`/`.popover` material (translucent vibrancy), large corner radius, subtle border, soft shadow.
- **List rows:** icon (SF Symbol by kind / source app icon / image thumbnail), one-line preview, secondary line (source app · relative time). Selected row uses accent-tinted highlight.
- **Preview pane:** rich render — formatted text, image at fit-to-pane, link cards, file rows. Metadata block below.
- **Footer:** Raycast-style hint bar with the active shortcuts.
- **Motion:** quick fade/scale-in on open (~120ms), no bouncy animations. Respect "Reduce Motion."
- **Theme:** follows system light/dark automatically; uses system accent color.
- **Empty states:** clean centered icon + text ("No clipboard history yet", "No results").
- **Fully keyboard-navigable:** ↑/↓ select, ←/→ or click switch filters, `⌘K` actions, type to search, `Esc` dismiss.

---

## 10. Settings window

- **General:** launch at login, panel position (center / under cursor / remember), `↵` behavior (default **always paste**; option: smart per type).
- **Hotkey:** recorder for the global open shortcut (default `⌥C`).
- **History:** retention policy — keep *all* / last *N* days / last *N* items (default: **last 1000 items**, pinned exempt). Max item size. Dedup scope (last item vs. entire history).
- **Privacy:** excluded apps list, toggle "ignore concealed/transient pasteboards" (default on), pause capture.
- **Images/OCR:** enable OCR (default on), OCR language(s), skip-OCR size threshold.
- **Data:** show DB size / item count, "Clear history…", "Reveal data folder in Finder".

---

## 11. Permissions & first-run

1. On first launch, show a small onboarding panel.
2. Request **Accessibility** (for paste-back) with a button that deep-links to the correct System Settings pane.
3. No special permission needed to *read* the pasteboard.
4. Register default hotkey; show it in onboarding.

---

## 12. Performance

- Polling cost is trivial; only deserialize on `changeCount` change.
- Virtualized list (`LazyVStack`/`List`) — handles tens of thousands of rows.
- Thumbnails cached on disk; full images loaded lazily only for the preview pane.
- OCR runs off the main thread, results written async; list updates when OCR completes.
- FTS5 keeps search instant even with large history.

---

## 13. Edge cases

- Rapid consecutive identical copies → dedup, no spam.
- Promised/lazy pasteboard data (some apps) → read what's available; skip if empty.
- Huge images → store, optionally skip OCR.
- Mixed text+image pasteboards → prefer image kind, keep text too.
- Item whose source file was deleted → "Open" shows a graceful error.
- DB migration strategy via GRDB migrations from day one.

---

## 14. Build milestones

- **M1 — Core capture:** menu bar agent, pasteboard polling, text capture, GRDB storage, dedup, basic list, paste-back. *(Usable skeleton.)*
- **M2 — Search & panel:** floating `NSPanel`, FTS5 search, two-pane layout, global hotkey, keyboard nav.
- **M3 — Images & OCR:** image capture, thumbnails, Vision OCR, OCR-aware search, open/Quick Look.
- **M4 — Actions:** `⌘K` menu, edit, pin, delete, open in browser, save image, copy OCR.
- **M5 — Settings & privacy:** settings window, retention pruning, concealed-type filter, app exclusions, launch at login.
- **M6 — Polish:** vibrancy, animations, empty states, onboarding, accent theming, icon.

---

## 15. Resolved decisions

1. **App name** — Succlippy.
2. **Default hotkey** — `⌥C` (Option+C), user-configurable in Settings.
   - ⚠️ Note: ⌥C is normally the `ç` character. Registering it globally means the app opens instead of typing `ç`. Fine if you don't type `ç`; if that ever bites, switch to `⌥⌘C` in Settings. Keeping ⌥C as the default per your call.
3. **Default retention** — keep the **last 1000 items**, drop oldest beyond that. Pinned items exempt from the cap. Adjustable in Settings.
4. **`↵` behavior** — **always paste** into the previously focused app, regardless of item kind. (For images, paste sends the image to the frontmost app; open/Quick Look remain on `Space` / `⌘O`.)
5. **Build/signing** — **ad-hoc local build** for this Mac. No paid Apple account needed. The build script produces a `Succlippy.app` bundle you can drop in `/Applications`.
