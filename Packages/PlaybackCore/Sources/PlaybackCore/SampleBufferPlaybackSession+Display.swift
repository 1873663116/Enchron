extension SampleBufferPlaybackSession {
    func clearDisplayedVideoImage() async {
        discardVideoFramesInFlight()
        await rendererSink.flush(removingDisplayedImage: true)
    }
}
