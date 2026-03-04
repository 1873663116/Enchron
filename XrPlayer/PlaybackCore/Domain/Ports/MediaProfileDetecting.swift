import Foundation

public protocol MediaProfileDetecting: AnyObject {
    func didDetectMediaProfile(_ profile: PlaybackCoreDomain.MediaProfile)
}
