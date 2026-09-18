English | [日本語](README.ja.md)

# Transom — External Title Bar + App Menu

The name Transom refers to the small window set above a door or window (a transom). It describes exactly what this app does: attach a separate bar above each target window.

A menu-bar resident app that adds an app name, a window title, and an operable app menu above each normal Mac window. The original Mac menu bar, title bar, red/yellow/green buttons, and toolbar are all left in place.

**Status: 0.1.0-dev — a development build still undergoing real-machine verification.** This is more than a design document: it includes the app itself, AX-based menu execution, tracking, build scripts, and tests. The first version was authored on Linux; on 2026-09-16 it was type-checked, linked, unit-tested (34 common-logic tests with Swift Testing), and packaged as an .app on macOS 26 / Apple Silicon / Command Line Tools (Swift 6.4). **On-hardware GUI acceptance testing (bar display, menu execution, Z-order, Spaces) is not complete. This is not a guaranteed-working finished app or a signed and notarized binary.** See `docs/VALIDATION.md` and `docs/ACCEPTANCE.md` for details.

## Getting started

Requirements: a Mac with a Swift 6 toolchain (Xcode or the matching Command Line Tools). The primary verification target is Apple Silicon / macOS 26. The minimum OS in the build settings is macOS 14, but that does not mean 14/15 have been verified on hardware.

In the extracted `Transom` folder, run from Terminal:

```bash
bash scripts/build-app.sh
open dist/Transom.app
```

After launch, **TR** appears at the top of the screen. Allow Transom under "System Settings → Privacy & Security → Accessibility". Edit the source by opening `Package.swift` in Xcode. There are no external Swift packages, Homebrew, or XcodeGen dependencies.

**On first run, try moving a normal window down about 40 points from the top of the screen.** The bar is a fully external strip 30 points high. It sits behind the window and continues in the same colour down to 48 pt below the window's top edge; hidden behind the window itself, it fills the gap that would otherwise show through the rounded corners, so nothing is overlaid in front of the window. When there is no room above, the bar is hidden rather than overlapping the original buttons or content. The TR menu item "Reserve Bar Space on Frontmost Window" can also create room, for that one window only — it is the single operation that moves (and, if needed, shrinks) the target window. There is no bulk move or automatic resize at launch.

## What's included

- App name display (document names appear only in the tool tip), retrieval of the app menu and items such as "File"/"Edit", and a `»` overflow indicator on narrow bars.
- Windows-style window buttons (minimize, maximize, close) at the right edge. Minimize and close press the window's own buttons via AX exactly once. Maximize fills the screen while leaving room for the bar, and pressing it again restores the previous frame. The buttons highlight on hover (close turns red), double-clicking the bar's empty stretch toggles maximize, and right-clicking anywhere on the bar opens a Windows-style menu (minimize / maximize / close, reserve bar space, exclude this app).
- Customizable bar colours. "Bar Color" in the TR menu recolours every bar's background, while "Active Bar" sets the focused-window marker: the system accent or any colour, shown as a top line or a filled bar. The line thickness is selectable from none (0) up to 5px; whenever a colour is painted, the title and button colours adjust automatically for contrast. "Bar Height" selects the strip height from 24 to 38px (30 is the default); text, glyphs and the app icon scale with it.
- Per-app exclusion: "Exclude Frontmost App" hides the bar for one app, "Excluded Apps" lists every exclusion for individual removal, and "Clear All Exclusions" resets the list. "Launch at Login" registers Transom as a macOS login item.
- Non-activating panels, dragging from the external title area, and tracking driven by both events and state verification.
- Hierarchical menus via standard NSMenu and command execution via AXPress on the original app. The original Mac menu remains.
- Re-verification of process/window generations, focus, document/selection state, and menu items. No automatic retries when a response is uncertain.
- Dynamic lookup of exact window IDs and relative Z-order placement with post-hoc verification. If a correct correspondence cannot be confirmed, display and interaction stop.
- Build scripts, 40 common-logic tests, an independent verification app TransomLab, review records, and an on-hardware checklist.
- The app's own UI (status menu, buttons, error messages) supports Japanese and English, following the OS language setting.

## Important limitations

Native full-screen windows, sheets, and modal dialogs are not decorated. Small windows under 280 points wide are also out of scope. The bar is not shown when it cannot fully fit: at screen edges, on windows spanning multiple displays, or on windows extending off-screen.

Menus are limited to what apps expose through accessibility. Full compatibility for lazily generated items, custom UIs, and Option-key alternatives is not implemented. Even for normal items, execution is aborted if a change or ambiguity is detected. For apps whose menus cannot be retrieved correctly, use the original Mac menu.

Spaces support is a display-projection approach: "switch the external bar's display to match the target windows currently visible". It does not make the bar a true child window inside WindowServer. There is no guarantee of unified animation with Mission Control, Stage Manager, or Space transitions.

The mere existence of a private API does not guarantee ABI compatibility or behaviour. Nothing here disables SIP, injects code into other apps, captures the screen, sends network traffic, or logs keystrokes. This is not a Mac App Store configuration.

## Build and test

```bash
# Mac: compile both apps + common tests + configuration checks
bash scripts/verify.sh

# Optimized build
bash scripts/build-app.sh --release

# Verification fixture for another app
bash scripts/build-app.sh --lab
open dist/TransomLab.app
```

`build-app.sh` signs with the self-signed `Transom` certificate when it exists in the login keychain, and falls back to ad-hoc signing otherwise. Apple notarization is not performed. Changing the signature or rebuilding may require re-granting accessibility permission. Quit the running old version from the TR menu before replacing it. Launch from a fixed `.app` location, and do not mix up the TCC permission target between `swift run`, Xcode runs, and the bundled app.

To force a specific identity (including `-` for ad-hoc), set the `CODESIGN_IDENTITY` environment variable. No signing keys or certificates are included.

## Development handoff

`docs/HANDOFF.md` is the on-hardware work order. `docs/REVIEW.md` lists fixed issues and unverified risks; `docs/ACCEPTANCE.md` gives the acceptance criteria. When handing off to Codex / Claude Code and similar agents, have them read the root `AGENTS.md` and these documents.

License: MIT. Referenced APIs and prior implementations are listed in `docs/SOURCES.md`.
