import CoreGraphics

public enum ShortcutRouting {
    public static func isLocalControl(keyCode: UInt16, modifiers: UInt64) -> Bool {
        let relevant = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        return modifiers & relevant == (CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
            && [UInt16(17), 1, 5, 53].contains(keyCode)
    }
    public static func capture(appActive: Bool, windowActive: Bool, desktopReady: Bool, enabled: Bool, keyCode: UInt16, modifiers: UInt64) -> Bool {
        appActive && windowActive && desktopReady && enabled && !isLocalControl(keyCode: keyCode, modifiers: modifiers)
    }
}
