import Foundation

enum PlaybackTimeFormatter {
    static func clock(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func preciseClock(_ seconds: Double, framesPerSecond: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if framesPerSecond > 0 {
            let frame = Int(seconds.truncatingRemainder(dividingBy: 1) * framesPerSecond)
            return String(format: "%02d:%02d:%02d.%02d", h, m, s, frame)
        }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
