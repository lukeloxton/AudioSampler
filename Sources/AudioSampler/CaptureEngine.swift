import Foundation
import ScreenCaptureKit
import CoreMedia

class CaptureEngine: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private(set) var isCapturing = false
    var onAudioBuffer: ((CMSampleBuffer) -> Void)?

    func startCapture(filter: SCContentFilter) async throws {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Minimise video overhead — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.sampler.capture", qos: .userInitiated))
        try await s.startCapture()
        stream = s
        isCapturing = true
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        stream = nil
        isCapturing = false
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        onAudioBuffer?(buffer)
    }

    // MARK: SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
    }
}
