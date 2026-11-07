import XCTest
@testable import Threadbear

/// The MonoCode look (Jordan, 6 Nov): glass and MonoCode's text sizes are
/// on for a new install, remembered, and the see-through slider runs
/// between the two mockups he picked.
@MainActor
final class GlassTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "glass-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        // Glass's sizes reach renderers through a shared atomic: put back
        // the shared model's, so other tests see what it says.
        Glass.monoStyleNow.store(Glass.shared.monoStyle, ordering: .relaxed)
        super.tearDown()
    }

    func testGlassAndMonoCodeSizesStartOn() {
        let glass = Glass(defaults: defaults)
        XCTAssertTrue(glass.enabled)
        XCTAssertTrue(glass.monoStyle)
        XCTAssertEqual(glass.strength, Glass.defaultStrength)
    }

    func testChoicesAreRemembered() {
        let glass = Glass(defaults: defaults)
        glass.enabled = false
        glass.strength = 0.8
        glass.monoStyle = false

        let again = Glass(defaults: defaults)
        XCTAssertFalse(again.enabled)
        XCTAssertEqual(again.strength, 0.8, accuracy: 0.0001)
        XCTAssertFalse(again.monoStyle)
    }

    func testStrengthStaysInRange() {
        let glass = Glass(defaults: defaults)
        glass.strength = 3
        XCTAssertEqual(glass.strength, 1)
        glass.strength = -1
        XCTAssertEqual(glass.strength, 0)
        defaults.set(9.0, forKey: Glass.strengthKey)
        XCTAssertEqual(Glass(defaults: defaults).strength, 1)
    }

    /// 0 is "Glass everywhere" (MonoCode's 62% window, 40% card), 1 is
    /// "Clearer glass" (45% and 28%).
    func testTheSliderRunsBetweenThePickedMockups() {
        let glass = Glass(defaults: defaults)
        glass.strength = 0
        XCTAssertEqual(glass.shellTint, 0.62, accuracy: 0.0001)
        XCTAssertEqual(glass.cardTint, 0.40, accuracy: 0.0001)
        glass.strength = 1
        XCTAssertEqual(glass.shellTint, 0.45, accuracy: 0.0001)
        XCTAssertEqual(glass.cardTint, 0.28, accuracy: 0.0001)
    }

    /// Renderers off the main thread read the atomic copy, and get
    /// MonoCode's 14 pt replies or Threadbear's 15 from it.
    func testTextSizesFollowTheChoiceOffTheMainThread() async {
        let glass = Glass(defaults: defaults)
        glass.monoStyle = true
        let mono = await Task.detached { TypeScale.body }.value
        glass.monoStyle = false
        let own = await Task.detached { TypeScale.body }.value
        let percent = CGFloat(TextZoom.current.load(ordering: .relaxed))
        XCTAssertEqual(mono, percent == 100 ? 14 : (14 * percent / 100).rounded())
        XCTAssertEqual(own, percent == 100 ? 15 : (15 * percent / 100).rounded())
    }
}
