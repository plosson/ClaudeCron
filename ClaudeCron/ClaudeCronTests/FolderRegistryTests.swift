import XCTest
@testable import ClaudeCron

final class FolderRegistryTests: XCTestCase {
    var registry: FolderRegistry!
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ccron-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        registry = FolderRegistry(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testInitiallyEmpty() {
        XCTAssertTrue(registry.folders.isEmpty)
    }

    func testAddFolder() {
        registry.add("/Users/me/project")
        XCTAssertEqual(registry.folders, ["/Users/me/project"])
    }

    func testAddDuplicateFolder() {
        registry.add("/Users/me/project")
        registry.add("/Users/me/project")
        XCTAssertEqual(registry.folders.count, 1)
    }

    func testRemoveFolder() {
        registry.add("/Users/me/project")
        registry.remove("/Users/me/project")
        XCTAssertTrue(registry.folders.isEmpty)
    }

    func testPersistence() {
        registry.add("/Users/me/project")
        let registry2 = FolderRegistry(defaults: defaults)
        XCTAssertEqual(registry2.folders, ["/Users/me/project"])
    }

    func testHomeAlwaysIncluded() {
        XCTAssertTrue(registry.allFolders.contains(NSHomeDirectory()))
    }

    func testAllFoldersIncludesRegisteredAndHome() {
        registry.add("/Users/me/project")
        let all = registry.allFolders
        XCTAssertTrue(all.contains(NSHomeDirectory()))
        XCTAssertTrue(all.contains("/Users/me/project"))
    }
}
