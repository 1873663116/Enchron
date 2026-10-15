import Testing
@testable import TidalEnvironment

struct TidalMotionTimelineTests {
    @Test func initialAppearanceDoesNotDissolveOrTurn() {
        var motion = TidalMotionTimeline()
        motion.request(.dark)
        #expect(motion.sample.darkMix == 1)
        #expect(motion.sample.skyYaw == 0)
        #expect(motion.sample.skyBlurAngle == 0)
        motion.request(.light)
        #expect(motion.sample.darkMix == 0)
        motion.advance(by: 0)
        motion.request(.dark)
        #expect(motion.sample.darkMix == 0)
        motion.advance(by: 0.6)
        #expect(abs(motion.sample.darkMix - 0.5) < 0.00001)
        #expect(abs(motion.sample.skyYaw - Float.pi / 2 - Float(0.6 * 2 * Double.pi / 7200)) < 0.00001)
        #expect(motion.sample.skyBlurAngle > 0)
        motion.advance(by: 0.6)
        #expect(motion.sample.darkMix == 1)
        #expect(motion.sample.skyBlurAngle == 0)
        #expect(abs(motion.sample.skyYaw - Float.pi - Float(1.2 * 2 * Double.pi / 7200)) < 0.00001)
    }

    @Test func reverseRequestContinuesFromDisplayedValues() {
        var motion = TidalMotionTimeline()
        motion.advance(by: 0)
        motion.request(.dark)
        motion.advance(by: 0.3)
        let before = motion.sample
        motion.request(.light)
        #expect(motion.sample.darkMix == before.darkMix)
        #expect(motion.sample.skyYaw == before.skyYaw)
        #expect(abs(motion.sample.skyBlurAngle - before.skyBlurAngle) < 0.00001)
        motion.advance(by: 0.6)
        motion.request(.light)
        motion.advance(by: 0.600001)
        #expect(motion.sample.darkMix == 0)
        #expect(motion.sample.skyBlurAngle == 0)
        #expect(abs(motion.sample.skyYaw - before.skyYaw - Float.pi - Float(1.200001 * 2 * Double.pi / 7200)) < 0.00001)
    }

    @Test func dailyMotionHasIndependentPeriods() {
        var motion = TidalMotionTimeline()
        motion.advance(by: 1800)
        #expect(abs(motion.sample.skyYaw - Float.pi / 2) < 0.00001)
        #expect(abs(motion.sample.orbitYaw - Float.pi) < 0.00001)
        motion.advance(by: 1800)
        #expect(abs(motion.sample.skyYaw - Float.pi) < 0.00001)
        #expect(motion.sample.orbitYaw == 0)
        motion.advance(by: 3600)
        #expect(motion.sample.skyYaw == 0)
        #expect(motion.sample.orbitYaw == 0)
    }
}
