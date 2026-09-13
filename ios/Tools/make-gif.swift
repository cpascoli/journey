import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Turns a simulator capture into the README GIF, using only system frameworks.
// usage: make-gif.swift <movie> <out.gif> <fps> <speedup> <width> [start end]
//   start/end: seconds into the movie to keep (default: all of it)
let args = CommandLine.arguments
guard args.count == 6 || args.count == 8,
      let fps = Double(args[3]), let speedup = Double(args[4]), let width = Int(args[5]) else {
    print("usage: make-gif.swift <movie> <out.gif> <fps> <speedup> <width> [start end]")
    exit(1)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let outURL = URL(fileURLWithPath: args[2])

let duration = try await asset.load(.duration).seconds
let start = args.count == 8 ? max(0, Double(args[6]) ?? 0) : 0
let end = args.count == 8 ? min(duration, Double(args[7]) ?? duration) : duration
guard end > start else {
    print(String(format: "empty window %.1f–%.1fs in a %.1fs movie", start, end, duration))
    exit(1)
}
// One output frame every `step` seconds of source time.
let step = speedup / fps
let count = Int((end - start) / step)

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)
generator.maximumSize = CGSize(width: width, height: 4000)

try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, count, nil) else {
    print("cannot write \(outURL.path)")
    exit(1)
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

// Identical consecutive frames (the pauses between steps) become one longer frame.
var pending: (image: CGImage, bytes: Data, frames: Int)?
var written = 0
func flush() {
    guard let pending else { return }
    let properties = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(pending.frames) / fps],
    ] as CFDictionary
    CGImageDestinationAddImage(destination, pending.image, properties)
    written += 1
}
for i in 0..<count {
    let time = CMTime(seconds: start + Double(i) * step, preferredTimescale: 600)
    guard let image = try? await generator.image(at: time).image,
          let bytes = image.dataProvider?.data as Data? else { continue }
    if let current = pending, current.bytes == bytes {
        pending?.frames += 1
        continue
    }
    flush()
    pending = (image, bytes, 1)
}
flush()
guard CGImageDestinationFinalize(destination) else {
    print("failed to encode \(outURL.path)")
    exit(1)
}
let bytes = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
print(String(format: "%d frames, source %.1f–%.1fs -> %.1fs @ %.0ffps, %.1f MB",
             written, start, end, (end - start) / speedup, fps, Double(bytes) / 1e6))
