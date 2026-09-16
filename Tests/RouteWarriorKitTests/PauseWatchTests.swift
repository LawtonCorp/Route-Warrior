import Foundation
import Testing
@testable import RouteWarriorKit

/// D-072: the two thresholds of a paused drive. Expected values are hand
/// arithmetic from the rule as written, not from running it.
struct PauseWatchTests {
    @Test func theDefaultsAreTwelveMinutesThenTwentyAsAsked() {
        let config = PauseWatch.Config()
        #expect(config.limit == 20 * 60)
        // 60% of twenty minutes and the twelve-minute cap agree exactly
        // at the default; that is why the default reads as one number.
        #expect(config.askAfter == 12 * 60)
    }

    @Test func nothingHappensBeforeTheQuestionIsDue() {
        #expect(PauseWatch.state(pausedFor: 0) == .waiting)
        #expect(PauseWatch.state(pausedFor: 11 * 60 + 59) == .waiting)
    }

    @Test func theQuestionIsDueAtTwelveMinutesAndStaysDueUntilTheLimit() {
        #expect(PauseWatch.state(pausedFor: 12 * 60) == .shouldAsk)
        #expect(PauseWatch.state(pausedFor: 19 * 60 + 59) == .shouldAsk)
    }

    @Test func theDriveStopsItselfAtTheLimit() {
        #expect(PauseWatch.state(pausedFor: 20 * 60) == .shouldStop)
        #expect(PauseWatch.state(pausedFor: 60 * 60) == .shouldStop)
    }

    /// A short limit scales the question down with it. Asking after the
    /// drive has already stopped itself would be a question nobody could
    /// answer.
    @Test func aShortLimitMovesTheQuestionInFrontOfIt() {
        let five = PauseWatch.Config(limit: 5 * 60)
        #expect(five.askAfter == 3 * 60)          // 60% of five minutes
        #expect(PauseWatch.state(pausedFor: 2 * 60, config: five) == .waiting)
        #expect(PauseWatch.state(pausedFor: 3 * 60, config: five) == .shouldAsk)
        #expect(PauseWatch.state(pausedFor: 5 * 60, config: five) == .shouldStop)
    }

    /// A long limit does not push the question out with it: twelve
    /// minutes of silence is long enough to be worth a nudge whatever
    /// the driver set the limit to.
    @Test func aLongLimitKeepsTheQuestionAtTwelveMinutes() {
        let hour = PauseWatch.Config(limit: 60 * 60)
        #expect(hour.askAfter == 12 * 60)
        #expect(PauseWatch.state(pausedFor: 12 * 60, config: hour) == .shouldAsk)
        #expect(PauseWatch.state(pausedFor: 59 * 60, config: hour) == .shouldAsk)
        #expect(PauseWatch.state(pausedFor: 60 * 60, config: hour) == .shouldStop)
    }

    /// Whatever the limit, the question comes first or not at all — the
    /// order of the two thresholds is the one thing that must never
    /// invert.
    @Test func theQuestionNeverComesAfterTheStop() {
        for minutes in [1, 3, 5, 10, 15, 20, 30, 45, 60, 180] {
            let config = PauseWatch.Config(limit: Double(minutes) * 60)
            #expect(config.askAfter <= config.limit, "limit \(minutes) min")
        }
    }
}
