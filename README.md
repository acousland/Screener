# Screener

Native remote desktop for a Mac mini and MacBook. Create a monitor when the mini is headless, change macOS HiDPI scaling, and receive a stream of up to 3840 × 2160 pixels on the MacBook.

Two applications share the same protocol:

- **Screener Server** runs in the mini's logged-in macOS desktop session. Its virtual monitor remains alive while the app is running, even when no viewer is connected.
- **Screener Client** runs on the MacBook. It displays the desktop with Metal and forwards input while the desktop has focus.

The initial implementation targets Apple silicon and macOS 15+. The intended test pair is an M4 mini and an M1 Pro MacBook running macOS 27 Golden Gate. See [validation](docs/VALIDATION.md) for verified behaviour and limitations.

## Install and connect

1. Download both application archives from the [Releases page](https://github.com/acousland/Screener/releases).
2. Move Screener Server to `/Applications` on the mini and Screener Client to `/Applications` on the MacBook.
3. On the mini, create the virtual monitor and choose your desktop scaling. The same modes are available in macOS System Settings → Displays.
4. Grant Screen & System Audio Recording to capture the desktop and sound, and Accessibility for remote keyboard/mouse control. Reopen the Server if macOS requests it.
5. Start the Server and copy its connection key.
6. On the MacBook, select the nearby server or enter its `.local` hostname/IP address, paste the key, and connect.

Click the remote desktop to focus it. **Control–Option–Esc** releases remote keyboard shortcuts. Disconnecting or moving focus releases held keys/buttons. Clipboard text sharing is off by default; enable it on the Server and use the Client's clipboard menu to transfer text explicitly.

To send macOS system shortcuts such as **Command–Space** to the mini, open **Session Controls → Session → Allow Shortcut Capture…** and grant Accessibility to **Screener Client on the MacBook**. Reopen the Client if necessary. With **Send keyboard shortcuts to mini** enabled, shortcuts are intercepted only while the active remote desktop has keyboard focus. Local controls, other apps and other Spaces keep their normal keyboard handling. The mini's Server also needs its own Accessibility permission to inject the input.

**Transparent Mode** is enabled by default in the Client's **View** menu. In full screen it hides Screener's controls, title bar, local menu bar and Dock, and shows only the remote desktop and its cursor. **Control–Option–T** toggles the mode. **Control–Option–Esc** exits transparent full screen and releases keyboard focus so you can return to the local controls. Local window controls and cursor visibility are restored when you leave the mode, switch apps or disconnect. Video retains the remote display's aspect ratio.

**Session Controls** opens on the regular macOS desktop before entering transparent full screen. It stays in its own Space while the remote desktop remains full screen. Use **Control–Option–S** to switch to the controls and back, or open **View → Session Controls…** and use **Return to Desktop**. You can also move the controls to another desktop in Mission Control. The window shares the current connection and lets you change resolution, video settings, Transparent Mode, keyboard shortcuts, automatic reconnect and clipboard transfers. Resolution changes apply immediately; choose **Apply Video Settings** to change frame rate or quality with a brief video pause and no disconnect. Live video settings require Server 0.1.2 or later; resolution controls also work with older servers.

**Responsive Cursor** is enabled by default with Server and Client 0.1.4 or later. The MacBook draws a local arrow immediately while the Server leaves the cursor out of the video. Change it in **View → Responsive Cursor** or **Session Controls → Session**. Turning it off restores the mini's cursor in the video, including text, resize and custom cursor shapes. Switching modes restarts capture briefly without disconnecting, and the Client follows each video's cursor metadata so it shows one pointer. Older Clients keep the embedded cursor; newer Clients connected to older Servers also use the embedded cursor automatically.

Responsive Cursor removes the video round trip from pointer movement; clicking, dragging windows and typing still depend on the mini and the video stream. H.264 uses hardware low-latency encoding, the decoder avoids display-order buffering, and the Client displays the newest decoded frame when its main thread is busy. For delayed desktop reactions, try **60 fps**, **Fast · 1080p** and **25 Mbps** in Session Controls, then **Apply Video Settings**. Lower video detail reduces capture, encoding and drawing work while preserving the desktop workspace and aspect ratio; text will be softer. **Balanced · 1440p** is an intermediate choice, while **Full · up to 4K** gives the sharpest text. End-to-end latency has not been measured on the target pair.

For better detail on a fast LAN, use **Full** with **75 or 100 Mbps**. Capture and H.264 metadata explicitly use Rec.709, and the Client renders to a tagged sRGB surface. Video remains lossy SDR H.264 4:2:0; it does not preserve HDR or the full Display P3 gamut. Higher quality uses more bandwidth and may increase delay on a congested connection.

**Mini system audio** is enabled by default with both apps at 0.1.4 or later. **Session Controls → Audio** lets you stop playback or change the local volume. The mini's sound plays through the MacBook's selected output, using stereo 48 kHz PCM over the same encrypted connection (about 3.1 Mbps in addition to video). This captures system sound, without microphone capture. With both apps at **0.1.5**, **Mute mini speakers** is enabled by default: Server mutes its default audio output once audio is forwarded, then restores its previous mute state when forwarding stops, the connection closes or Server quits. Turn it off to hear both Macs. Volume is never changed. Output-device changes are checked every second, and previous devices are restored; deliberate manual unmuting relinquishes Screener's ownership. A recovery record restores an owned mute after an interrupted Server run when it reopens. Outputs that lack software mute (such as some HDMI devices) show an error; select built-in speakers or mute the external output directly. Playback drops old audio under backpressure and limits its scheduled buffer to 125 ms; it is not synchronized to delayed video for movie playback. Older Servers do not send audio or offer host muting, and the controls indicate that an update is needed.

**Game Mouse**, added in 0.1.5, sends relative movement for first-person games. First focus the game on the mini using normal desktop control, then choose **View → Game Mouse** or **Session Controls → Session** and click the viewer. **Control–Option–G** toggles it; **Control–Option–Esc** releases the pointer and keyboard. The local pointer is hidden and detached from movement while the viewer is active, allowing continuous turning without hitting a screen edge. Adjust sensitivity in Session Controls. Mouse buttons and scrolling remain available. Focus loss, Space changes and disconnects restore the local pointer. Turn it off to use desktop menus and absolute pointing. It injects Core Graphics movement events; games that require direct hardware/IOHID input may ignore them. Compatibility with The Stanley Parable still needs a live check on the target pair.

Use a stable LAN connection. Wired Ethernet on the mini is recommended. TCP port **49555** must be reachable; discovery uses Bonjour `_screener._tcp`. There is no cloud service or relay. Do not expose the server directly to the public internet.

## Display scaling

Desktop workspace, backing pixels, and network pixels are independent. For example, “looks like 2560 × 1440” can render at 5120 × 2880 and be downsampled into a 3840 × 2160 stream. The virtual monitor offers both **16:10** MacBook workspaces and **16:9** workspaces, with the ratio shown beside each resolution. The 16:10 choices include 1280 × 800, 1440 × 900, 1512 × 945, 1680 × 1050, 1728 × 1080, 1920 × 1200, 2240 × 1400, 2560 × 1600, 3008 × 1880 and 3360 × 2100, all with HiDPI backing modes. A 2560 × 1600 workspace renders at 5120 × 3200 and streams at 3456 × 2160 to preserve 16:10 within the video limit.

New installations default to 1920 × 1200; existing saved scaling is preserved. After updating Screener Server, quit and reopen it to recreate the virtual monitor with the additional modes. Select **Screener 4K · Virtual** on the Server, then choose a resolution in Session Controls or the Server's scaling picker. The **16:10 · HiDPI** modes match the usable area below the MacBook Pro's notch. With 0.1.5, **1512 × 982 · 14″ full screen · HiDPI** and **1728 × 1117 · 16″ full screen · HiDPI** match the complete panel, including the strip beside the notch. Their backing sizes are 3024 × 1964 and 3456 × 2234. In Transparent Mode the Client ignores safe-area padding and opts out of macOS's camera compatibility scaling; the physical notch still covers the content behind it. The 16-inch mode is downsampled to 3340 × 2160 by the video limit, with sub-pixel aspect differences from even-pixel rounding. Physical monitors offer the modes returned by macOS and retain their aspect ratio within the 4K stream limit.

Virtual display creation uses the private `CGVirtualDisplay` family, resolved at runtime with a user-facing failure if unavailable. This is a directly distributed app, not a Mac App Store submission. A physical monitor remains an available capture source.

## Build

Install Xcode 16+ (Xcode 27 for development on Golden Gate), then:

```sh
swift test --disable-sandbox
scripts/build-apps.sh
```

Both bundles are written to `dist/`. Builds use Developer ID if available, otherwise ad hoc signing for development. Sparkle 2.10.0 is pinned through SwiftPM. For a network-restricted build, copy the official `Sparkle.xcframework` to `Vendor/` and its `LICENSE` to `Vendor/Sparkle-LICENSE`, then set `SCREENER_LOCAL_SPARKLE=1`.

Compilation, tests, signing and notarization run locally. GitHub Actions is disabled; GitHub hosts the source, releases and update feeds.

`ScreenerDiagnostics` reports permissions and hardware decode capability without requesting permissions. `ScreenerDiagnostics --virtual-display` creates a temporary monitor, reports the actual modes and verifies both 16:9 and 16:10 HiDPI workspaces; `--hold` keeps it alive for 30 seconds for inspection. Run the virtual-display diagnostic with Screener Server closed.

## Updates and releases

Both apps include Sparkle and a **Check for Updates…** menu. Server and Client have separate signed feeds and bundle IDs, with a shared Ed25519 signing identity. The apps require signed feeds and verify update archives. Updates are checked automatically, but installation is user-controlled so a server update does not silently interrupt a remote session.

See [RELEASING.md](docs/RELEASING.md) for Developer ID signing, notarization, signature verification, GitHub publication, and keeping the update key safe. The release script refuses to publish ad hoc development builds.

## Current scope

H.264 4:2:0 SDR video, up to 4K output with optional 1440p/1080p caps, 30/60 fps targets, stereo system audio, one viewer, one shared display, keyboard/mouse input, manual clipboard text transfer and bounded automatic reconnect. File transfer, microphone forwarding, HDR, pre-login/FileVault unlock, multiple concurrent viewers and internet traversal are not implemented.

The random 256-bit connection key is stored in Keychain and used for mutually authenticated TLS-PSK/AES-GCM. Rotating it disconnects existing connections; it must then be replaced on clients. Captured desktop pixels, audio and input are never sent before authentication. The protocol bounds message sizes and validates display/video/audio/input data.

## Licence

MIT. Sparkle uses its own licence, bundled with each app. Private display interface declarations are informed by Khaos Tian's work and [DeskPad](https://github.com/Stengo/DeskPad); see [THIRD_PARTY.md](docs/THIRD_PARTY.md).
