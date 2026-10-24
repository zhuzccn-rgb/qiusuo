import LexiconCore
import CoreAudio
import Foundation

public struct AudioInputDevice: Equatable, Sendable {
    public var id: AudioDeviceID
    public var name: String
    public var uid: String
    public var transport: UInt32
}

/// Built-in / USB / Bluetooth mics only. BlackHole, ZoomAudioDevice, Teams loopback are silent unless another app is piping into them.
public enum AudioInputPicker {
    public static func lectureMic() -> AudioInputDevice? {
        let inputs = inputDevices()
        if let current = defaultInput(), isUsableHardware(current) {
            return current
        }
        if let builtIn = inputs.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) {
            return builtIn
        }
        return inputs.first(where: isUsableHardware)
    }

    public static func isUsableHardware(_ device: AudioInputDevice) -> Bool {
        isUsableHardware(name: device.name, uid: device.uid, transport: device.transport)
    }

    public static func isUsableHardware(name: String, uid: String, transport: UInt32) -> Bool {
        if isKnownHardware(transport) { return true }
        if isKnownVirtual(transport) { return false }
        return !looksLikeLoopback(name: name, uid: uid)
    }

    public static func looksLikeLoopback(name: String, uid: String) -> Bool {
        let blob = "\(name) \(uid)".lowercased()
        let needles = [
            "blackhole",
            "soundflower",
            "loopback",
            "msloopback",
            "microsoft teams audio",
            "zoomaudiodevice",
            "zoom.us.zoom",
            "vb-cable",
            "voicemeeter",
            "groundcontrol"
        ]
        return needles.contains(where: { blob.contains($0) })
    }

    public static func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { id in
            guard hasInput(id) else { return nil }
            return AudioInputDevice(
                id: id,
                name: stringValue(id, kAudioObjectPropertyName) ?? L10n.text("输入 \(id)"),
                uid: stringValue(id, kAudioDevicePropertyDeviceUID) ?? "",
                transport: transportType(id)
            )
        }
    }

    public static func defaultInput() -> AudioInputDevice? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return inputDevices().first(where: { $0.id == device })
            ?? AudioInputDevice(
                id: device,
                name: stringValue(device, kAudioObjectPropertyName) ?? L10n.text("默认输入"),
                uid: stringValue(device, kAudioDevicePropertyDeviceUID) ?? "",
                transport: transportType(device)
            )
    }

    private static func isKnownHardware(_ transport: UInt32) -> Bool {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return true
        default:
            return false
        }
    }

    private static func isKnownVirtual(_ transport: UInt32) -> Bool {
        switch transport {
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAirPlay:
            return true
        default:
            return false
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(sys, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func transportType(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }

    private static func stringValue(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        let ptr = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        ptr.initialize(to: nil)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, ptr) == noErr else { return nil }
        guard let cf = ptr.pointee else { return nil }
        return cf.takeUnretainedValue() as String
    }
}
