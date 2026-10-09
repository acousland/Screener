Adds mini system audio, faster pointer movement, video detail controls, explicit color handling and capture of macOS system shortcuts.

Update **both Server and Client to 0.1.4** using **Check for Updates…**. Use **Control–Option–S** to open Session Controls while in transparent full screen.

- **Audio:** the mini's system sound plays through the MacBook's selected output by default. Session Controls → Audio provides a playback toggle and local volume. Allow Screen & System Audio Recording for Server on the mini. Stereo 48 kHz PCM adds about 3.1 Mbps, uses the encrypted connection and bounds playback buffering to 125 ms. It does not capture microphones or mute the mini's speakers; movie lip-sync is not implemented.
- **Desktop responsiveness:** hardware low-latency H.264, reduced decoder buffering and newest-frame presentation. Choose 60 fps, Fast · 1080p and 25 Mbps to reduce video work while keeping the same desktop workspace. Balanced · 1440p is another option. Lower detail softens text; end-to-end latency improvement has not yet been measured on the target pair.
- **Responsive Cursor:** enabled by default; the MacBook draws an immediate local arrow and excludes the mini's pointer from video. Turn it off under View or Session Controls when you need exact text/resize/custom cursor shapes. Older peers retain the embedded cursor.
- **Video quality:** explicit Rec.709 capture/encoding and sRGB display output address implicit color handling. Full · up to 4K with 75 or 100 Mbps offers the most detail on a fast LAN. Video remains lossy SDR H.264 4:2:0.
- **Command–Space and other system shortcuts:** grant Accessibility to Screener Client on the MacBook using Session Controls → Session → Allow Shortcut Capture…. Reopen Client if needed. Shortcuts go to the mini only when the active viewer has keyboard focus and remote shortcuts are enabled. Control–Option–S/T/Esc remain local controls.

Live changes briefly restart capture with the connection kept open. New audio, cursor and video-detail fields remain compatible with older peers; update both apps to access all the controls.

The connection key and existing display scaling are preserved. Apple High Performance Screen Sharing can still conflict with Screener's virtual monitor; use Standard Screen Sharing while setting it up.

Both apps are built and signed locally, then notarized by Apple. Sparkle verifies the signed update feeds and archives. GitHub Actions remains disabled.
