Adds Transparent Mode for full screen: only the remote desktop is visible, with Screener's controls, title bar, local menu bar, Dock and duplicate local cursor hidden. The preference is enabled by default and can be changed in **View → Transparent Mode**.

Use **Control–Option–T** to toggle Transparent Mode, or **Control–Option–Esc** to leave transparent full screen and return to local controls. Normal window controls and cursor visibility return when you switch apps, disconnect or leave the mode. The remote display's aspect ratio is preserved.

Also fixes connection failures that previously appeared only as “The other Mac disconnected.”

- The Server sends the rejection or capture failure before closing the connection.
- Both applications display the reason, including missing Screen Recording permission or an unavailable monitor.
- The Client preserves message order and stops automatically retrying a rejected session.
- The Server records session errors in the macOS log and includes its screen-capture usage description.

On the mini, grant Screener Server Screen Recording permission in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the Server. The connection key is unchanged by this update.

Apple High Performance Screen Sharing can remove Screener’s virtual monitor and leave its fixed identity unavailable. Use Standard Screen Sharing while setting up Screener. Recovery from that virtual-display conflict remains a known limitation.

Both apps are built and signed locally, then notarized by Apple. Sparkle verifies the signed update feeds and archives. GitHub Actions remains disabled.
