import Foundation
import AVFoundation
import CoreMedia

class WAVRecorder {
    let outputURL: URL
    private var audioFile: AVAudioFile?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start() {}  // file created lazily on first buffer to match source format exactly

    func append(_ sampleBuffer: CMSampleBuffer) {
        let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numFrames > 0 else { return }

        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: fmtDesc)

        // Create file on first buffer using the stream's native format
        if audioFile == nil {
            audioFile = try? AVAudioFile(forWriting: outputURL, settings: format.settings)
        }
        guard let audioFile else { return }

        // Get audio buffer list
        var ablSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &ablSize,
            bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: nil
        )

        let ablPtr = UnsafeMutableRawPointer.allocate(
            byteCount: ablSize, alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { ablPtr.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: ablSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: ablPtr.assumingMemoryBound(to: AudioBufferList.self),
            deallocator: nil
        ) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(numFrames)

        try? audioFile.write(from: pcmBuffer)
    }

    func stop(completion: @escaping (URL?) -> Void) {
        audioFile = nil  // flushes and closes
        completion(outputURL)
    }
}
