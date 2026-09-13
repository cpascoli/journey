import Foundation
import ImageIO
import UniformTypeIdentifiers

// Copies sample photos, re-stamping each with a capture time and GPS position
// inside one of the visits seeded by Journey/Demo/DemoData.swift (keep in sync),
// so the day view matches them to places.
// usage: stage-demo-photos.swift <source dir> <out dir>
let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: stage-demo-photos.swift <source dir> <out dir>")
    exit(1)
}

let shots: [(hour: Int, minute: Int, latitude: Double, longitude: Double)] = [
    (9, 20, 13.7437, 100.4889),
    (10, 5, 13.7440, 100.4886),
    (12, 40, 13.7999, 100.5500),
    (13, 25, 13.8002, 100.5496),
    (17, 25, 13.7314, 100.5414),
    (18, 10, 13.7318, 100.5409),
]

let fm = FileManager.default
let sources = (try fm.contentsOfDirectory(atPath: args[1]))
    .filter { ["jpg", "jpeg", "heic"].contains(($0 as NSString).pathExtension.lowercased()) }
    .sorted()
    .map { URL(fileURLWithPath: args[1]).appendingPathComponent($0) }
guard !sources.isEmpty else {
    print("no photos in \(args[1])")
    exit(1)
}
try fm.createDirectory(atPath: args[2], withIntermediateDirectories: true)

let calendar = Calendar.current
let today = calendar.startOfDay(for: .now)
let exifDate = DateFormatter()
exifDate.dateFormat = "yyyy:MM:dd HH:mm:ss"
let seconds = TimeZone.current.secondsFromGMT()
let offset = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)

for (index, shot) in shots.enumerated() {
    let source = sources[index % sources.count]
    guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else { continue }
    let taken = calendar.date(bySettingHour: shot.hour, minute: shot.minute, second: 0, of: today)!
    let stamp = exifDate.string(from: taken)
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
            kCGImagePropertyExifOffsetTimeOriginal: offset,
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: abs(shot.latitude),
            kCGImagePropertyGPSLatitudeRef: shot.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(shot.longitude),
            kCGImagePropertyGPSLongitudeRef: shot.longitude >= 0 ? "E" : "W",
        ],
    ]
    let out = URL(fileURLWithPath: args[2]).appendingPathComponent(String(format: "demo-%02d.jpg", index + 1))
    guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
    CGImageDestinationAddImageFromSource(destination, image, 0, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { continue }
    print("\(out.lastPathComponent) <- \(source.lastPathComponent) @ \(stamp)")
}
