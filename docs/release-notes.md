Adds a separate **Session Controls** window for use on another macOS desktop/Space while the remote desktop stays in transparent full screen. The controls open on the regular desktop before entering transparent full screen, and can be moved with Mission Control.

Use **Control–Option–S** to switch between the remote desktop and its controls, or choose **View → Session Controls…** and **Return to Desktop**. Closing the controls does not disconnect the session; the shortcut reopens them.

- Change resolution during the session.
- Change frame rate and quality with **Apply Video Settings**. Video pauses briefly while capture restarts; the connection remains open.
- Change Transparent Mode, keyboard shortcut forwarding and automatic reconnect.
- Transfer clipboard text, view errors or disconnect.

Update **both Server and Client** to 0.1.2 for live frame-rate and quality changes. A new Client connected to an older Server still supports resolution changes and disables unsupported live video controls. The connection key is unchanged by this update.

Transparent Mode keeps the remote window's controls hidden while the settings window has focus. The local menu bar, Dock and cursor return for the controls. **Control–Option–T** toggles Transparent Mode; **Control–Option–Esc** still exits transparent full screen.

Apple High Performance Screen Sharing can remove Screener’s virtual monitor and leave its fixed identity unavailable. Use Standard Screen Sharing while setting up Screener. Recovery from that virtual-display conflict remains a known limitation.

Both apps are built and signed locally, then notarized by Apple. Sparkle verifies the signed update feeds and archives. GitHub Actions remains disabled.
