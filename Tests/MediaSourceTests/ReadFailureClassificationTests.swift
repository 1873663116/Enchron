#if DEBUG
import Foundation
import Testing

@testable import MediaSource

@Suite(.serialized)
struct ReadFailureClassificationTests {
    @Test("retryable HTTP statuses map to transport interruption")
    func retryableStatuses() {
        for status in [408, 429, 500, 502, 503, 504] {
            #expect(MediaSourceReadFailure(httpStatusCode: status) == .transportInterrupted)
        }
    }

    @Test("permanent HTTP statuses map to their own failures")
    func permanentStatuses() {
        #expect(MediaSourceReadFailure(httpStatusCode: 403) == .accessDenied)
        #expect(MediaSourceReadFailure(httpStatusCode: 404) == .resourceMissing)
        #expect(MediaSourceReadFailure(httpStatusCode: 416) == .invalidData)
        #expect(MediaSourceReadFailure(httpStatusCode: 418) == nil)
    }
}
#endif
