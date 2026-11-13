import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Animated GIFs from screen recordings, written by ImageIO.
nonisolated enum GIF {
    static let framesPerSecond = 10

    /// shortcut: ImageIO holds every frame until the file is finalized (about 12 bytes a pixel, measured), so all the
    /// frames of one GIF share this many pixels, about 1 GB. Write the GIF ourselves, frame by frame, to lift it.
    static let pixelBudget = 80_000_000.0

    /// How big the frames are for `count` frames of an area of `size` points: 1× at most (never the Retina pixels),
    /// and smaller when the recording is long or large enough to go over the budget.
    static func frameSize(for size: CGSize, frames count: Int) -> CGSize {
        let scale = min(1, (pixelBudget / (Double(count) * size.width * size.height)).squareRoot())
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Writes `movie`, a recording of an area of `size` points, as a looping GIF.
    static func write(movie: URL, of size: CGSize, to url: URL) async throws {
        let asset = AVURLAsset(url: movie)
        let count = max(1, Int(try await asset.load(.duration).seconds * Double(framesPerSecond)))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = frameSize(for: size, frames: count)
        var frames: [CGImage] = []
        // All at once: asking for one frame at a time seeks each time and takes four times as long.
        for await result in generator.images(for: (0..<count).map { CMTime(value: CMTimeValue($0), timescale: CMTimeScale(framesPerSecond)) }) {
            frames.append(try result.image)
        }
        try write(frames, to: url)
    }

    static func write(_ frames: [CGImage], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary) // 0: forever
        let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / Double(framesPerSecond)]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(destination, frame, delay) }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
