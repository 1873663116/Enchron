extension SampleBufferPlaybackSession {
    public func clearDisplayedVideoImage() async {
        await rendererSink.flush(removingDisplayedImage: true)
    }
}
