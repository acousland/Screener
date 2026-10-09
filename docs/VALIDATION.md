# Validation

This document must reflect performed checks, not planned checks. Compilation alone does not establish remote-desktop usability or sustained 4K60 performance.

## Local results (2026-10-09)

Compiled both arm64 applications locally in Debug and Release using Xcode 27.0 on macOS 27.0.1 (build 26A434). Both release bundles are signed with Developer ID Application: Aaron Cousland (5NF98M544G) and pass `codesign --verify --deep --strict`.

The unrestricted local test run completed **12 passing tests, no skips and no failures**. This includes encrypted/authenticated TLS loopback, rejection of a client with the wrong connection key, and hardware 3840 × 2160 H.264 encode/decode. The protocol, bounds, geometry, queue-capacity and malformed-video checks also pass. See `.build/test-local-release.log` locally for the exact results.

The runtime diagnostic detected the private display classes and H.264 hardware decode support. A temporary virtual monitor was successfully created, and macOS returned HiDPI workspaces of 1920 × 1080 backed by 3840 × 2160, 2560 × 1440 backed by 5120 × 2880, and 3008 × 1692 backed by 6016 × 3384. The monitor was released when the diagnostic exited. See `.build/virtual-display-local-release.log` locally for the enumerated modes.

Sparkle 2.10.0 is embedded in each app, with separate Server and Client feed URLs. Both apps require signed feeds and verification of update archives before extraction. The existing Ed25519 public identity matches its private seed; the private seed's local directory/file permissions are 0700/0600 respectively, and git ignores all private credentials and build products.

Apple accepted notarization of both release applications. Both bundles have stapled tickets, pass `xcrun stapler validate`, and are accepted by Gatekeeper as Notarized Developer ID. The separate ZIP archives and appcasts are signed and verified with Sparkle's official `sign_update` tool, and the archive SHA-256 checksums match.

All compilation, tests, signing and release preparation run locally. No GitHub Actions workflows are included. A two-Mac capture/input session, installation of a newer build through Sparkle, and sustained 4K60 performance still require checks on the target pair.

## Automated coverage

- Stream framing across arbitrary packet boundaries, malformed lengths and unknown message types.
- Video packet timestamps, input bounds, letterboxing/coordinate conversion, connection-key parsing, and supported session settings.
- TLS loopback with matching keys, and rejection of a client with the wrong key.
- Hardware 3840 × 2160 H.264 encode/decode and rejection of invalid video configurations.
- ZIP archive and appcast Ed25519 signature verification during release preparation.

## Two physical Macs

These checks require the M4 mini and M1 Pro MacBook with the necessary macOS permissions:

1. Start the server headless; confirm a virtual monitor appears in Displays.
2. Select 1920 × 1080, 2560 × 1440 and 3008 × 1692 HiDPI modes in macOS and in the Client. Confirm text size changes and the stream remains within 4K.
3. Connect/disconnect a physical monitor while streaming. Select either display and verify preserved aspect ratio and input coordinates.
4. Type, drag windows, right-click, double-click, scroll, and use Command shortcuts with at least the normal keyboard layout and trackpad.
5. Hold a key/button while disconnecting and verify the remote desktop is not left with a stuck input state.
6. Test clipboard text in both directions, including the sharing-disabled case.
7. Interrupt the network and verify reconnection, then rotate the server key and verify the old key fails.
8. Measure capture/encode/network/decode latency, frame rate and text quality at 25/45/75 Mbps. The current UI reports a target frame rate, not a measured value.
9. Check Open at Login and behaviour after logout/restart. The server does not provide FileVault or login-window access.
10. Install a newer signed build through each Sparkle feed and verify the correct app is updated with its settings preserved.

Record results and OS build numbers here before claiming the release is validated on the target pair.
