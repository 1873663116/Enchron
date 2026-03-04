import Foundation

public enum AppConstants {
    public static let progressRetentionDays = 5
    public static let defaultGestureDisambiguationWindowMilliseconds = 100

    public enum Playback {
        public static let supportedVideoExtensions: Set<String> = [
            "mp4", "mkv", "avi", "mov", "m4v", "webm", "ts", "m2ts", "flv"
        ]
    }

    public enum Spatial {
        public static let nearDistanceMeters = 4.0
        public static let comfortableDistanceMeters = 8.0
        public static let cinemaDistanceMeters = 14.0
    }
}
