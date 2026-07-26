extension SampleBufferPlaybackSession {
    func clearDisplayedVideoImage() async {
        await rendererSink.flush(removingDisplayedImage: true)
    }
}
