import Foundation
import CoreAudio

public protocol AudioOutputControl {
    func defaultOutputUID() throws -> String
    func isMuted(_ uid: String) throws -> Bool
    func setMuted(_ muted: Bool, for uid: String) throws
}

/// Own only the mute changes we make, and journal them before touching the device.
/// All calls are confined to the Server's main thread (or one test thread).
public final class AudioOutputMuteLease {
    private let output: AudioOutputControl
    private let save: ([String: Bool]) -> Void
    private var pending: [String: Bool]
    private var activeUID: String?
    public init(output: AudioOutputControl, pending: [String: Bool] = [:], save: @escaping ([String: Bool]) -> Void) {
        self.output = output; self.pending = pending; self.save = save
    }
    public func transition(to uid: String?) throws {
        if let uid, activeUID == uid {
            // Honor a manual unmute rather than later overwriting the user's new state.
            if pending[uid] != nil, try !output.isMuted(uid) { pending.removeValue(forKey: uid); save(pending) }
            try restorePending(except: uid)
            return
        }
        activeUID = nil
        var restoreError: Error?
        do { try restorePending() } catch { restoreError = error }
        if let uid {
            if try !output.isMuted(uid) {
                pending[uid] = false; save(pending)
                do { try output.setMuted(true, for: uid) }
                catch {
                    // A failed setter may still have changed the device; try to roll it back.
                    if (try? output.isMuted(uid)) == false { pending.removeValue(forKey: uid); save(pending) }
                    else if (try? output.setMuted(false, for: uid)) != nil { pending.removeValue(forKey: uid); save(pending) }
                    throw error
                }
            }
            activeUID = uid
        }
        if let restoreError { throw restoreError }
    }
    private func restorePending(except active: String? = nil) throws {
        var failure: Error?
        for previous in Array(pending.keys) where previous != active {
            do {
                if try output.isMuted(previous) { try output.setMuted(pending[previous]!, for: previous) }
                pending.removeValue(forKey: previous); save(pending)
            } catch { failure = error } // Retain the journal if an output is unplugged or restoration fails.
        }
        if let failure { throw failure }
    }
}

public struct CoreAudioOutputControl: AudioOutputControl {
    public init() {}
    public func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device))
        guard device != kAudioObjectUnknown else { throw ScreenerError.message("The mini has no audio output device.") }
        return try uid(for: device)
    }
    public func isMuted(_ uid: String) throws -> Bool {
        let device = try device(for: uid)
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { throw unsupportedMute }
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value))
        return value != 0
    }
    public func setMuted(_ muted: Bool, for uid: String) throws {
        let device = try device(for: uid)
        var address = muteAddress, settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
            AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            throw unsupportedMute
        }
        var value: UInt32 = muted ? 1 : 0
        try check(AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value))
        guard try isMuted(uid) == muted else { throw ScreenerError.message("The mini's audio output did not accept the mute change.") }
    }
    private var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private var unsupportedMute: ScreenerError {
        .message("The mini's selected output does not support software mute. Choose its built-in speakers in Sound settings, or mute that output's speakers directly.")
    }
    private func uid(for device: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value))
        guard let value else { throw ScreenerError.message("The mini's audio output has no device identity.") }
        return value.takeRetainedValue() as String
    }
    private func device(for uid: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
        guard size >= MemoryLayout<AudioDeviceID>.size else { throw ScreenerError.message("The mini has no audio output devices.") }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }
        try check(status)
        guard let device = devices.first(where: { (try? self.uid(for: $0)) == uid }) else { throw ScreenerError.message("An audio output awaiting mute restoration is disconnected.") }
        return device
    }
    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw ScreenerError.message("The mini's audio output mute control is unavailable (\(status)).") }
    }
}

@MainActor public final class AudioOutputMuteController {
    public var onError: ((String) -> Void)?
    private let output = CoreAudioOutputControl()
    private let lease: AudioOutputMuteLease
    private var enabled = false
    private var lastError: String?
    public init(defaults: UserDefaults = .standard) {
        let key = "audioOutputMuteRecovery"
        let pending = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        lease = AudioOutputMuteLease(output: output, pending: pending) { journal in
            defaults.set(journal, forKey: key)
            defaults.synchronize() // Save the original state before a device can be left muted by a crash.
        }
    }
    public func setEnabled(_ enabled: Bool) { self.enabled = enabled; refresh() }
    public func refresh() {
        do {
            try lease.transition(to: enabled ? output.defaultOutputUID() : nil)
            lastError = nil
        } catch {
            let text = error.localizedDescription
            if lastError != text { lastError = text; onError?(text) }
        }
    }
}
