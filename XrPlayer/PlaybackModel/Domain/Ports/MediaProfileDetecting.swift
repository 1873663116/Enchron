import Foundation

public nonisolated protocol MediaProfileDetecting: AnyObject {
    func didDetectMediaProfile(_ profile: PlaybackModel.MediaProfile)
}
