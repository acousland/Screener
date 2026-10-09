Screener's first preview provides a native server for the Mac mini and a client for the MacBook.

- A persistent virtual monitor for headless operation, with macOS HiDPI scaling modes.
- Hardware-encoded H.264 streaming up to 3840 × 2160, at a selectable 30 or 60 fps target.
- Direct encrypted LAN connections authenticated with a random connection key.
- Remote keyboard, mouse, trackpad scrolling, and optional clipboard text transfer.
- Separate Sparkle update feeds for the Server and Client applications.

Both downloads are Developer ID signed and notarized by Apple. Sparkle verifies the signed update feeds and archives. All compilation, tests, signing and notarization were performed locally; GitHub Actions is disabled.

Install **Screener Server** on the mini and **Screener Client** on the MacBook. Grant the Server Screen Recording and Accessibility permissions, start it, then copy its connection key to the Client.

This preview requires Apple silicon and macOS 15 or later. Headless operation requires a logged-in macOS desktop session. Audio, file transfer, pre-login access, HDR, and internet relays are not included in this version. The virtual monitor uses a private macOS interface and must be checked after OS updates. Text is carried using H.264 4:2:0; it does not match Apple's 4:4:4 High Performance mode for every kind of coloured text.

The frame rate is a target, not a guarantee. See docs/VALIDATION.md for the checks completed on the release build and the remaining checks on two physical Macs.
