import CoreAudio
import XCTest
import LexiconSpeech

final class AudioInputPickerTests: XCTestCase {
    func testBuiltInMicIsUsable() {
        XCTAssertTrue(AudioInputPicker.isUsableHardware(
            name: "MacBook Pro Microphone",
            uid: "BuiltInMicrophoneDevice",
            transport: kAudioDeviceTransportTypeBuiltIn
        ))
    }

    func testUSBMicIsUsableEvenIfNameMentionsZoom() {
        XCTAssertTrue(AudioInputPicker.isUsableHardware(
            name: "Zoom H6",
            uid: "USB_H6",
            transport: kAudioDeviceTransportTypeUSB
        ))
    }

    func testBlackHoleIsRejected() {
        XCTAssertFalse(AudioInputPicker.isUsableHardware(
            name: "BlackHole 2ch",
            uid: "BlackHole2ch_UID",
            transport: kAudioDeviceTransportTypeVirtual
        ))
        XCTAssertTrue(AudioInputPicker.looksLikeLoopback(name: "BlackHole 2ch", uid: "BlackHole2ch_UID"))
    }

    func testZoomAndTeamsLoopbacksAreRejected() {
        XCTAssertFalse(AudioInputPicker.isUsableHardware(
            name: "ZoomAudioDevice",
            uid: "zoom.us.zoomaudiodevice.001",
            transport: kAudioDeviceTransportTypeVirtual
        ))
        XCTAssertFalse(AudioInputPicker.isUsableHardware(
            name: "Microsoft Teams Audio",
            uid: "MSLoopbackDriverDevice_UID",
            transport: kAudioDeviceTransportTypeVirtual
        ))
    }

    func testLectureMicPrefersBuiltInOnThisMac() {
        guard let mic = AudioInputPicker.lectureMic() else {
            XCTFail("no input")
            return
        }
        XCTAssertTrue(AudioInputPicker.isUsableHardware(mic), mic.name)
        XCTAssertFalse(AudioInputPicker.looksLikeLoopback(name: mic.name, uid: mic.uid))
    }
}
