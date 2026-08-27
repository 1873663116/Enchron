import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Device Hub"
guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("window list unavailable\n".utf8))
    exit(2)
}
var found: [[String: Any]] = []
for entry in raw {
    guard let name = entry[kCGWindowOwnerName as String] as? String, name == owner else { continue }
    guard let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { continue }
    guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
    let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
    let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
    guard width > 200, height > 200 else { continue }
    found.append([
        "number": entry[kCGWindowNumber as String] as? Int ?? 0,
        "x": (bounds["X"] as? NSNumber)?.doubleValue ?? 0,
        "y": (bounds["Y"] as? NSNumber)?.doubleValue ?? 0,
        "width": width,
        "height": height,
    ])
}
let payload = try JSONSerialization.data(withJSONObject: ["owner": owner, "windows": found], options: [.sortedKeys])
FileHandle.standardOutput.write(payload)
FileHandle.standardOutput.write(Data("\n".utf8))
