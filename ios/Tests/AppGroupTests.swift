import Testing
@testable import QuestLock

/// Swift Testing: `@Test` ≈ JUnit 5's `@Test`, `#expect` ≈ `assertTrue`/`assertEquals`.
/// Phase 0 only proves the test target is wired up; Phase 1 adds the ScheduleMath tests.
struct AppGroupTests {
    @Test func appGroupIDMatchesBundlePrefix() {
        #expect(AppGroup.id == "group.com.mohammadshaw.questlock")
    }

    @Test func sharedDefaultsRoundTrip() {
        let key = "phase0.smokeTest"
        AppGroup.defaults.set("ok", forKey: key)
        defer { AppGroup.defaults.removeObject(forKey: key) }
        #expect(AppGroup.defaults.string(forKey: key) == "ok")
    }
}
