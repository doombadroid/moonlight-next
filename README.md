# MoonLume

[![CI](https://github.com/doombadroid/moonlight-next/actions/workflows/ci.yml/badge.svg)](https://github.com/doombadroid/moonlight-next/actions/workflows/ci.yml)
[![Build IPA](https://github.com/doombadroid/moonlight-next/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/doombadroid/moonlight-next/actions/workflows/build-ipa.yml)

MoonLume is a game and desktop streaming client for iPhone, built for the **iPhone Duo** foldable. It streams games and the full desktop from a PC running [Sunshine](https://github.com/LizardByte/Sunshine). It is a fork of [Moonlight for iOS](https://github.com/moonlight-stream/moonlight-ios): the streaming core is the same, and the app around it is new.

MoonLume works with any host OS (Windows, macOS or Linux) running stock Sunshine. Nothing else needs to be installed on the PC. A few options depend on what the host's Sunshine can do, and their settings say so.

> **Status:** sideload-only and in active development. Builds are compiled by CI; most features from October 2026 have not been tested on a device yet.

## Install

MoonLume is not on the App Store. Install it with [SideStore](https://sidestore.io) or any other sideloading tool.

- **SideStore source:** `https://raw.githubusercontent.com/doombadroid/moonlight-next/master/sidestore-source.json`
- **Latest IPA:** [Releases](https://github.com/doombadroid/moonlight-next/releases/latest) (unsigned; your sideloading tool signs it)

Requires iOS 17 or later. The iPhone Duo features need iOS 27.1.

## iPhone Duo

- **Fold-aware layouts.** The app follows the hinge. Folded, the outer display gets a phone layout. Unfolded, the inner display gets a two-pane launcher. Folding or unfolding mid-stream re-fits the video and the controls.
- **Tabletop input deck.** Half-fold the phone like a laptop or a Nintendo DS and the lower half becomes an input deck: a trackpad on top and a full keyboard below, or a gamepad.
- **Folded gamepad.** On the outer display the on-screen controls are packed to the edges and keep clear of the camera hole.
- **Layouts per posture.** Control layouts are saved separately for the folded, phone-landscape and unfolded postures, and optionally per game.

## Screenshots

iPhone Duo, folded and unfolded:

<p>
<img src="docs/screenshots/duo-launcher-folded.webp" alt="MoonLume's launcher on the folded iPhone Duo, showing a PC and its games" height="360">
<img src="docs/screenshots/duo-race-folded.webp" alt="SuperTuxKart streaming on the folded iPhone Duo with the on-screen gamepad" height="360">
</p>
<p>
<img src="docs/screenshots/duo-race-unfolded.webp" alt="SuperTuxKart streaming full screen on the unfolded iPhone Duo" width="49%">
</p>

Half-folded (tabletop), with the keyboard and trackpad deck or the gamepad deck on the lower half:

<p>
<img src="docs/screenshots/duo-tabletop-keyboard.webp" alt="The half-folded iPhone Duo streaming SuperTuxKart above the keyboard and trackpad deck" width="49%">
<img src="docs/screenshots/duo-tabletop-gamepad.webp" alt="The half-folded iPhone Duo streaming SuperTuxKart above the gamepad deck" width="49%">
</p>

Standard iPhone (from the simulator's demo mode, which shows a sample PC and placeholder game art):

<p>
<img src="docs/screenshots/iphone/01-launcher.webp" alt="MoonLume's launcher on an iPhone, showing a PC and its games" height="420">
<img src="docs/screenshots/iphone/06-settings-gyro.webp" alt="MoonLume's gyro aiming settings on an iPhone" height="420">
</p>
<p>
<img src="docs/screenshots/iphone/02-stream-land.webp" alt="A stream on an iPhone in landscape with the on-screen gamepad" width="49%">
<img src="docs/screenshots/iphone/03-stream-menu-land.webp" alt="The stream menu open on an iPhone" width="49%">
</p>
<p>
<img src="docs/screenshots/iphone/04-edit-controls-land.webp" alt="Edit Controls on an iPhone: the layout editor bar over the on-screen gamepad" width="49%">
<img src="docs/screenshots/iphone/04b-widget-picker-land.webp" alt="The Add Widget picker on an iPhone" width="49%">
</p>
<p>
<img src="docs/screenshots/iphone/05-input-deck-land.webp" alt="The keyboard and trackpad deck on an iPhone" width="49%">
</p>

<details>
<summary>App Store screenshots (iPhone Duo)</summary>

<p>
<img src="docs/screenshots/appstore/iphone-duo-inner-1-race-unfolded.webp" alt="App Store screenshot: iphone duo inner 1 race unfolded" height="300">
<img src="docs/screenshots/appstore/iphone-duo-inner-2-tabletop-keyboard.webp" alt="App Store screenshot: iphone duo inner 2 tabletop keyboard" height="300">
<img src="docs/screenshots/appstore/iphone-duo-inner-3-tabletop-keyboard-flat.webp" alt="App Store screenshot: iphone duo inner 3 tabletop keyboard flat" height="300">
<img src="docs/screenshots/appstore/iphone-duo-inner-4-tabletop-gamepad.webp" alt="App Store screenshot: iphone duo inner 4 tabletop gamepad" height="300">
<img src="docs/screenshots/appstore/iphone-duo-inner-5-tabletop-gamepad-flat.webp" alt="App Store screenshot: iphone duo inner 5 tabletop gamepad flat" height="300">
<img src="docs/screenshots/appstore/iphone-duo-outer-1-launcher.webp" alt="App Store screenshot: iphone duo outer 1 launcher" height="300">
<img src="docs/screenshots/appstore/iphone-duo-outer-2-race-folded.webp" alt="App Store screenshot: iphone duo outer 2 race folded" height="300">
</p>
</details>

<sub>Device frames are from Apple Design Resources. The game shown is [SuperTuxKart](https://supertuxkart.net) (GPL-3.0, art CC-BY-SA), streamed from a Linux PC running Sunshine.</sub>

## Features

### Launcher
- SwiftUI launcher: PCs in a sidebar, games in a grid, pairing, and adding a PC by IP address or hostname.
- Hide apps, and show them again with View All Apps.
- A Now Running card resumes or quits the game in progress.
- Each PC's menu has Refresh apps, Test Network and Remove Computer. Pull down to refresh.
- One-tap **Launch** on a PC: resumes the running game, or starts the last one you played.
- PC details sheet with addresses, MAC address and pair state, with copy actions.
- Wake-on-LAN, home-screen quick actions, and an **Open PC** action for Shortcuts, Siri, Spotlight and the Action button.
- Placeholder tiles for games without box art. Sensible first-run defaults for the device.

### Settings
- Settings are reachable from the launcher and mid-stream.
- Favorites (long-press any setting to pin it), collapsible sections, search, and (i) tips that explain the less obvious options.
- A sidebar of pages on wide screens.
- An About page with the version, credits, licenses and the SideStore source URL.

### Video and audio
- **Renderers:** System (the Moonlight default) or VideoToolbox. VideoToolbox adds decode-time stats and **x2 frame interpolation**, so a 60 fps stream plays at 120 fps. Interpolation needs iOS 26 on a device that supports it, a stream at no more than half the screen's refresh rate, and costs about half a frame of latency.
- Frame pacing: Lowest latency, Balanced, or Smoothest with a 1 to 4 frame queue.
- **Resolution:** presets from 720p to 4K, Native, Safe area (native, clear of the camera cut-out), or a custom size up to 7680×4320.
- 30, 60 or 120 fps (120 on 120 Hz screens), and bitrate up to 800 Mbps.
- Codec: Auto, H.264, HEVC or AV1. Only codecs the phone can decode are offered.
- **HDR:** HDR has to be turned on in the PC's display settings.
- **Full color (YUV 4:4:4):** HEVC only. The PC's encoder must support it, otherwise the stream stays at normal color.
- **Full color range.**
- HDR and 4:4:4 appear only on phones that can decode them.
- **Sound:** stereo, 5.1 or 7.1. On iOS 18 and later, surround plays as spatial audio on headphones.
- **Audio controls:** a stream volume slider, play audio on the PC, "let other apps keep playing", and mute in background.

### Stream
- **••• menu:** gyro pause, controller mouse, picture in picture, edit controls, touch on/off, keyboard and trackpad deck, settings, stats, disconnect, quit app.
- **Picture in picture:** leaving the app floats the stream, and closing the window ends it.
- **Background keep-alive:** without picture in picture, stay connected for 1, 5, 15 or 30 minutes in the background.
- **External display:** show the video on a USB-C or AirPlay screen while the phone keeps the controls and keyboard. Native resolution then matches that screen.
- **Stats overlay:**
  - Simple is one line: fps, bitrate, latency, packet loss and decode time.
  - Detailed adds average and peak bitrate, frames buffered, host latency and **stutter diagnostics**.
  - Stutter diagnostics show a 30-second network delay graph and split hitches between the network and the PC. A tip appears when hitches repeat on a fixed rhythm, which usually means Wi-Fi scanning.
  - Decode time needs the VideoToolbox renderer.
- Optimize game settings: the host adjusts the game's settings for the stream, on hosts that support it.
- Plain-language hints when a stream disconnects.
- Optional periodic dummy input that can reduce Wi-Fi power-save stutter.

### On-screen controls and widgets
- **On-screen controls:** Off, Auto, Simple or Full. Auto shows the full gamepad when no controller is connected, and otherwise only the buttons the controller lacks.
- Built-in gamepad with press highlight and sliding from one button to the next.
- **Layout editor:**
  - Drag, resize, fade or hide each control.
  - Snapping guides and undo.
  - Named layouts with templates, and JSON import and export.
- **Widgets** you can place anywhere:
  - Buttons for any gamepad button, key, mouse button (including Back/Forward) or scroll notch.
  - A library of shortcuts (Ctrl+C, Alt+Tab, Win+D and more) and custom key chords.
  - Macros with timed steps, and turbo buttons.
  - Floating sticks, a look pad with inertia, analog trigger strips, and a WASD pad with walk and sprint keys.
  - A mouse touchpad, a screen pad that maps the whole host screen for direct pointing, scroll strips, and a PlayStation touchpad.
  - A blocker that absorbs touches, so a resting palm doesn't press anything.
  - Gyro aim and pause buttons, and buttons for menu actions.
  - Folders that collapse and dock to the screen edge. A folder can peek: it shows its contents while held, and letting go over a widget presses it.
  - Buttons that latch on tap. Widgets can be set as movable, so you can drag them during play.
  - A live overlay of your physical controller.

### Touch, mouse and keyboard
- **Touch modes:** Touchpad, Touchscreen, Native or Off.
  - Native sends each finger to the host as its own touch point, up to 11, with pressure where the screen reports it.
  - Native needs a Windows or Linux host. On other hosts it acts like Touchscreen.
  - An optional fast-swipe zone on the right moves Native touches faster, for camera swipes.
- **Trackpad gestures:**
  - Two-finger vertical and horizontal scroll, with momentum.
  - Pinch to zoom.
  - Tap-then-hold to drag.
  - Pointer speed, and reversed wheel.
- In Touchscreen mode, two fingers scroll, pinch to zoom and tap to right-click.
- An optional "click when the finger lifts" setting is available. With it, a finger that rests briefly before moving drags.
- **Deck keyboard:** an fn layer with F1 to F12, Home/End/Page keys and Delete, plus a Win/Super key. It has haptics that match the system keyboard.
- **Soft keyboard:** an editable key bar (Esc, Tab, modifiers, arrows, F-keys), a 3, 4 or 5-finger tap toggle, and a height adjustment.
- **Hardware keyboard:**
  - Ctrl+Alt+Shift hotkeys for disconnect, quit, settings, stats, mouse capture and cursor.
  - Globe key as Escape.
- Mouse cursor modes. An optional edge swipe opens the stream menu.

### Controllers, gyro and haptics
- **Emulated controller:** Automatic, Xbox or PlayStation.
  - Choose PlayStation and the host's virtual pad reports motion from the source set in Motion sensors: Auto, Phone, Controller or Off. Auto uses a connected controller's gyro if it has one, and the phone's otherwise.
  - Steam Input and games with native gyro then work without a physical controller.
  - Only Windows and Linux hosts support this. Sunshine on macOS has no virtual controller.
- **Gyro aiming:**
  - The phone or a controller's gyro moves the mouse or the right stick.
  - It can run always or while L2 is held. An assigned controller button can hold to aim, toggle aiming, or hold to pause.
  - Pause it from the stream menu.
  - Per-axis sensitivity, invert Y, tilt-to-steer, a minimum stick offset, and drift calibration.
- **Rumble:**
  - On the phone when no controller is connected, or always.
  - Swap motors, or turn rumble off.
- DualSense adaptive triggers on a real DualSense, when the host emulates a DualSense. In practice this means Sunshine on Linux.
- Rumble for the Razer Kishi V3 Pro XL and the GameSir G8+ MFi.
- **Stick settings:**
  - A stick minimum offset lifts small movements past a game's deadzone.
  - Swap A/B and X/Y.
  - A Multiple controllers toggle. Turned off, every pad is player 1.
- **Controller mouse:** one stick moves the PC's pointer and the other scrolls.
  - Choose the stick, the click buttons and the speed.
  - Turn it on with Select + R3 or from the stream menu. The game doesn't see the controller while it's on.
- **Controller navigation:**
  - Drive the launcher and settings with a gamepad, with button hints.
  - Hold the Guide button (configurable) in a stream for a quick radial menu.

## Building

MoonLume builds with **Xcode 27.1** and the iOS 27.1 SDK. The Duo APIs are compiled in only with that SDK.

```sh
git clone --recursive https://github.com/doombadroid/moonlight-next.git
```

If you cloned without `--recursive`, run `git submodule update --init --recursive`.

Open `Moonlight.xcodeproj` and pick the **Moonlight** scheme. To run on a device, set your team under Signing & Capabilities and change the bundle identifier (`com.doombadroid.moonlume`) to one of your own.

Layout of the code:
- **`MoonlightNext/`:** the Swift app: launcher, settings, input deck, widgets, gyro, picture in picture and the other new features. It is iOS only.
- **`Limelight/`:** the Objective-C streaming core inherited from Moonlight, shared with the tvOS target.

CI (`.github/workflows/ci.yml`) builds iOS and tvOS on every push. `build-ipa.yml` runs on every push to `master` or by hand. It builds an unsigned IPA, publishes a release and updates the SideStore source. It also launches the app on an iPhone Duo simulator to check that it starts.

## Credits and license

MoonLume is licensed under the GPLv3, like Moonlight.

- [Moonlight for iOS](https://github.com/moonlight-stream/moonlight-ios) and its contributors wrote the streaming core and the original app.
- [VoidLink](https://github.com/TrueZhuangJia/moonlight-ios-NativeMultiTouchPassthrough) (GPLv3) served as a reference for several features. Code adapted from it is marked in the source.
- [moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c) handles the streaming protocol.
