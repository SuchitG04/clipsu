# Succlippy

A native macOS clipboard history manager — long searchable history, image OCR, a
Raycast-style two-pane panel, and a ⌘K actions menu. Menu-bar agent, zero external
dependencies (only Apple system frameworks).

See [`SPEC.md`](SPEC.md) for the full design.

## Features

- **Global hotkey** to open the panel (default **⌥C**, configurable in Settings).
- **Long history** kept in SQLite (default: last **1000** items; pinned items never expire).
- **Search** across text, links, file names, source app, **and text recognized inside images** (on-device Vision OCR), backed by SQLite FTS5.
- **Images**: captured to disk with thumbnails; open / Quick Look / save / copy recognized text.
- **Actions menu (⌘K)**: paste, paste as plain text, copy, edit, pin/unpin, open in browser, open/Quick Look image, save image, copy OCR text, reveal source app, delete, clear all.
- **Paste-back**: press **↵** to paste the entry straight into the app you were using.
- **Privacy**: ignores password-manager / transient pasteboards by default; per-app exclusion list; everything stays local.
- **macOS aesthetic**: vibrant translucent panel, rounded corners, SF Symbols, system accent, light/dark aware.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode / Swift toolchain (Swift 5.9+)

## Build & run

```bash
./build.sh          # release build → build/Succlippy.app (ad-hoc signed)
./build.sh run      # build, then launch
./build.sh debug    # debug build
```

Then move `build/Succlippy.app` to `/Applications` if you like, and launch it. It lives
in the menu bar (look for the clipboard icon) — there is no Dock icon.

To develop:

```bash
swift build         # compile
swift test          # run the unit tests (18 tests)
```

## First run / permissions

- On first launch Succlippy asks for **Accessibility** permission. This is only needed for
  **paste-back** (synthesizing ⌘V into the previous app). Grant it in
  *System Settings → Privacy & Security → Accessibility*. Without it, entries are still
  placed on the clipboard — just press ⌘V yourself.
- No permission is required to read the clipboard or run OCR.

> Tip: the default hotkey **⌥C** is also the `ç` character. If you ever need to type `ç`,
> change the shortcut in *Settings → Shortcut* (e.g. to ⌥⌘C).

## Keyboard shortcuts (in the panel)

| Key | Action |
|---|---|
| type | search |
| ↑ / ↓ | move selection |
| ↵ | paste selected entry |
| ⌘↵ | paste as plain text |
| ⌘K | open actions menu |
| ⌘C | copy to clipboard |
| ⌘E | edit (text entries) |
| ⌘P | pin / unpin |
| ⌘O | open link in browser / open image |
| ⌘S | save image |
| Space | Quick Look image (when search is empty) |
| ⌘⌫ | delete entry |
| ⌘, | open Settings |
| Esc | close menu / panel |

## Where data lives

```
~/Library/Application Support/Succlippy/
├── db.sqlite      # history + search index
├── images/        # full images
└── thumbs/        # thumbnails
```

Clear everything from *Settings → Data → Clear All History*, or just delete that folder.

## Architecture

- **`SucclippyCore`** (library, unit-tested): models, SQLite wrapper + schema/FTS5 search,
  content classification, image storage, Vision OCR.
- **`Succlippy`** (executable): app lifecycle, clipboard monitor, capture pipeline,
  paste service, Carbon global hotkey, login item, and the SwiftUI/AppKit panel + settings UI.

## Notes / known caveats

- Ad-hoc signed for personal use. Moving it between Macs or distributing it would need a
  Developer ID signature.
- The floating panel is a non-activating `NSPanel` so your previous app keeps focus for
  paste-back. If keyboard focus into the search field ever feels off on your setup, that's
  the area to check first.
