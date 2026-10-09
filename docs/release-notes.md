Adds the missing **16:10 HiDPI resolutions** for the MacBook's usable screen area. Both the Client and Server show **16:10** or **16:9** beside the relevant resolutions.

The virtual monitor now offers 1280 × 800, 1440 × 900, 1512 × 945, 1680 × 1050, 1728 × 1080, 1920 × 1200, 2240 × 1400, 2560 × 1600, 3008 × 1880 and 3360 × 2100 HiDPI workspaces. Existing 16:9 modes remain available. New installations default to 1920 × 1200; existing saved scaling is preserved.

Update both apps using **Check for Updates…**, then quit and reopen **Screener Server** so its virtual monitor is recreated with the new modes. Select **Screener 4K · Virtual** on the Server, and choose a **16:10 · HiDPI** resolution under **Session Controls → Display → Resolution**. Use **Control–Option–S** to switch to the controls while the remote desktop stays in transparent full screen.

A 2560 × 1600 HiDPI workspace streams at 3456 × 2160, preserving 16:10 within the existing video limit. This update also fixes floating-point rounding that could shave two pixels off some scaled streams. These modes match the area below the notch, rather than the extra notch/menu-bar strip. Physical monitors continue to offer their own macOS-supported modes.

The connection key is unchanged. Apple High Performance Screen Sharing can still conflict with Screener's virtual monitor; use Standard Screen Sharing while setting it up.

Both apps are built and signed locally, then notarized by Apple. Sparkle verifies the signed update feeds and archives. GitHub Actions remains disabled.
