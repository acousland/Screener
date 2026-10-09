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
4. Grant Screen Recording to capture the desktop and Accessibility for remote keyboard/mouse control. Reopen the Server if macOS requests it.
5. Start the Server and copy its connection key.
6. On the MacBook, select the nearby server or enter its `.local` hostname/IP address, paste the key, and connect.

Click the remote desktop to focus it. **Control–Option–Esc** releases remote keyboard shortcuts. Disconnecting or moving focus releases held keys/buttons. Clipboard text sharing is off by default; enable it on the Server and use the Client's clipboard menu to transfer text explicitly.

**Transparent Mode** is enabled by default in the Client's **View** menu. In full screen it hides Screener's controls, title bar, local menu bar and Dock, and shows only the remote desktop and its cursor. **Control–Option–T** toggles the mode. **Control–Option–Esc** exits transparent full screen and releases keyboard focus so you can return to the local controls. Local window controls and cursor visibility are restored when you leave the mode, switch apps or disconnect. Video retains the remote display's aspect ratio.

**Session Controls** opens on the regular macOS desktop before entering transparent full screen. It stays in its own Space while the remote desktop remains full screen. Use **Control–Option–S** to switch to the controls and back, or open **View → Session Controls…** and use **Return to Desktop**. You can also move the controls to another desktop in Mission Control. The window shares the current connection and lets you change resolution, video settings, Transparent Mode, keyboard shortcuts, automatic reconnect and clipboard transfers. Resolution changes apply immediately; choose **Apply Video Settings** to change frame rate or quality with a brief video pause and no disconnect. Live video settings require Server 0.1.2 or later; resolution controls also work with older servers.

Use a stable LAN connection. Wired Ethernet on the mini is recommended. TCP port **49555** must be reachable; discovery uses Bonjour `_screener._tcp`. There is no cloud service or relay. Do not expose the server directly to the public internet.

## Display scaling

Desktop workspace, backing pixels, and network pixels are independent. For example, “looks like 2560 × 1440” can render at 5120 × 2880 and be downsampled into a 3840 × 2160 stream. The server advertises backing modes for logical workspaces including 1920 × 1080, 2560 × 1440 and 3008 × 1692, and enumerates the modes actually returned by macOS. Portrait and non-16:9 physical displays retain their aspect ratio within the 4K stream limit.

Virtual display creation uses the private `CGVirtualDisplay` family, resolved at runtime with a user-facing failure if unavailable. This is a directly distributed app, not a Mac App Store submission. A physical monitor remains an available capture source.

## Build

Install Xcode 16+ (Xcode 27 for development on Golden Gate), then:

```sh
swift test --disable-sandbox
scripts/build-apps.sh
```

Both bundles are written to `dist/`. Builds use Developer ID if available, otherwise ad hoc signing for development. Sparkle 2.10.0 is pinned through SwiftPM. For a network-restricted build, copy the official `Sparkle.xcframework` to `Vendor/` and its `LICENSE` to `Vendor/Sparkle-LICENSE`, then set `SCREENER_LOCAL_SPARKLE=1`.

Compilation, tests, signing and notarization run locally. GitHub Actions is disabled; GitHub hosts the source, releases and update feeds.

`ScreenerDiagnostics` reports permissions and hardware decode capability without requesting permissions. `ScreenerDiagnostics --virtual-display` creates a temporary monitor, reports the actual modes and verifies 1920 × 1080 and 2560 × 1440 HiDPI; `--hold` keeps it alive for 30 seconds for inspection.

## Updates and releases

Both apps include Sparkle and a **Check for Updates…** menu. Server and Client have separate signed feeds and bundle IDs, with a shared Ed25519 signing identity. The apps require signed feeds and verify update archives. Updates are checked automatically, but installation is user-controlled so a server update does not silently interrupt a remote session.

See [RELEASING.md](docs/RELEASING.md) for Developer ID signing, notarization, signature verification, GitHub publication, and keeping the update key safe. The release script refuses to publish ad hoc development builds.

## Current scope

H.264 4:2:0 video, 4K output, 30/60 fps targets, one viewer, one shared display, keyboard/mouse input, manual clipboard text transfer and bounded automatic reconnect. Audio, file transfer, HDR, pre-login/FileVault unlock, multiple concurrent viewers and internet traversal are not implemented.

The random 256-bit connection key is stored in Keychain and used for mutually authenticated TLS-PSK/AES-GCM. Rotating it disconnects existing connections; it must then be replaced on clients. Captured desktop pixels and input are never sent before authentication. The protocol bounds message sizes and validates display/video/input data.

## Licence

MIT. Sparkle uses its own licence, bundled with each app. Private display interface declarations are informed by Khaos Tian's work and [DeskPad](https://github.com/Stengo/DeskPad); see [THIRD_PARTY.md](docs/THIRD_PARTY.md).
