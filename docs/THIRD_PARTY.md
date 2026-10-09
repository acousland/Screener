# Third-party components

- **Sparkle 2.10.0**, https://github.com/sparkle-project/Sparkle. Used unchanged for authenticated app updates. Its full licence is copied into each application bundle.
- **Private CoreGraphics display interfaces**, originally reverse-engineered by Khaos Tian and documented in https://github.com/Stengo/DeskPad/blob/main/DeskPad/CGVirtualDisplayPrivate.h. Screener's bridge is an independent implementation using runtime class lookup and the documented selectors. No DeskPad Swift implementation is copied.

The project uses Apple's ScreenCaptureKit, VideoToolbox, CoreGraphics, Metal/CoreImage, Security and Network frameworks.

The HiDPI mode convention and optional descriptor properties are cross-checked against Chromium's native test utility: https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm. With HiDPI enabled, virtual mode dimensions are logical and the backing buffer is twice as large in each dimension.
