#if os(macOS)
import CoreAudio
import Foundation

struct MicDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

// Core Audio による入力デバイス(マイク)の列挙と選択。macOS 専用。
enum AudioDevices {
    /// 入力チャンネルを持つデバイスの一覧
    static func inputDevices() -> [MicDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id -> MicDevice? in
            guard hasInput(id),
                  let name = stringProperty(id, kAudioObjectPropertyName),
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return MicDevice(id: id, uid: uid, name: name)
        }
    }

    /// 保存済み UID から現在のデバイス ID を解決する(接続状況で ID は変わるため UID で保持する)
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.id
    }

    static func name(forUID uid: String) -> String? {
        inputDevices().first { $0.uid == uid }?.name
    }

    /// OS の現在の既定入力デバイス
    static func systemDefaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(ptr.assumingMemoryBound(to: AudioBufferList.self))
        for buffer in list where buffer.mNumberChannels > 0 { return true }
        return false
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var unmanaged: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &unmanaged)
        guard status == noErr, let cf = unmanaged?.takeRetainedValue() else { return nil }
        return cf as String
    }
}
#endif
