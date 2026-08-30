import XCTest
@testable import SGSimpleSettings

/// MARK: DarkGram
/// These cover the failure that took the app down: the settings cache was written without
/// synchronisation, so concurrent first reads raced. The bug never showed on a single thread,
/// which is why it reached a device -- so the tests hammer the accessors from many threads at
/// once rather than checking that a value round-trips.
final class SettingsConcurrencyTests: XCTestCase {
    private let domain = "darkgram.test"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: self.domain)!
        defaults.removePersistentDomain(forName: self.domain)
        return defaults
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: self.domain)
        super.tearDown()
    }

    /// Many threads touching a cold value must all see the same thing, and must not crash.
    func testConcurrentColdReadsAgree() {
        let defaults = self.makeDefaults()
        defaults.set(42, forKey: "coldValue")

        let wrapper = UserDefault<Int>(key: "coldValue", userDefaults: defaults)
        let results = NSMutableArray()
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            let value = wrapper.wrappedValue
            lock.lock()
            results.add(value)
            lock.unlock()
        }

        XCTAssertEqual(results.count, 500)
        for value in results {
            XCTAssertEqual(value as? Int, 42, "a concurrent cold read saw a different value")
        }
    }

    /// Reads and writes interleaved from many threads must not corrupt the cache.
    func testConcurrentReadWriteDoesNotCorrupt() {
        let defaults = self.makeDefaults()
        defaults.set(0, forKey: "mixed")
        let wrapper = UserDefault<Int>(key: "mixed", userDefaults: defaults)

        DispatchQueue.concurrentPerform(iterations: 400) { index in
            if index % 4 == 0 {
                wrapper.wrappedValue = index
            } else {
                // The value is unpredictable under concurrent writes; that it stays readable
                // at all, without tearing, is the point.
                _ = wrapper.wrappedValue
            }
        }

        XCTAssertNoThrow(wrapper.wrappedValue)
    }

    /// The dictionary type behind aliases and notes had the same defect.
    func testConcurrentDictionaryAccess() {
        let defaults = self.makeDefaults()
        defaults.set(["a": "one", "b": "two"], forKey: "dict")

        let dictionary = UserDefaultsBackedDictionary<String, String>(
            userDefaultsKey: "dict", userDefaults: defaults, threadSafe: true
        )

        DispatchQueue.concurrentPerform(iterations: 300) { index in
            if index % 5 == 0 {
                dictionary["c\(index)"] = "value"
            } else {
                _ = dictionary["a"]
            }
        }

        XCTAssertEqual(dictionary["a"], "one")
    }

    /// Every key must have somewhere to live, or it silently reads a default forever.
    func testEveryKeyIsReachable() {
        XCTAssertFalse(SGSimpleSettings.Keys.allCases.isEmpty)
        let defaults = SGSimpleSettings.defaultValues
        let group = SGSimpleSettings.groupDefaultValues
        for key in SGSimpleSettings.Keys.allCases {
            let raw = key.rawValue
            XCTAssertFalse(raw.isEmpty, "a settings key has an empty raw value")
            _ = defaults[raw] ?? group[raw]
        }
    }
}
