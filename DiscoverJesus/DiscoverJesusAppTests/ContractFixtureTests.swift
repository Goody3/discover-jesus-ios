import XCTest
@testable import DiscoverJesus

final class ContractFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: ContractFixtureTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json"),
            "Missing bundled contract fixture: \(name)"
        )
        return try Data(contentsOf: url)
    }

    func testPageSummariesDecodeBackendContractFields() throws {
        let pages = try JSONDecoder().decode([PageSummary].self, from: fixture("page-summaries"))
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].id, 1)
        XCTAssertEqual(pages[0].publicId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(pages[0].slug, "home")
        XCTAssertEqual(pages[0].title, "Home")
        XCTAssertTrue(pages[0].isPublished)
        XCTAssertFalse(pages[1].isPublished)
    }

    func testPublishedEnvelopeAndSupportedClientSections() throws {
        let parsed = try PageContentLogic.parsePagePayload(data: fixture("published-page"))
        let page = parsed.renderedPage
        XCTAssertEqual(page.id.uuidString.lowercased(), "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(page.title, "Contract fixture")
        XCTAssertEqual(page.locale, "en-US")
        XCTAssertEqual(page.version, 1)
        XCTAssertFalse(parsed.jsonText.isEmpty)
        XCTAssertEqual(page.sections.map {
            PageContentLogic.sectionKind(for: $0, hasNavBarSection: true)
        }, [
            .button, .header, .text, .list, .navBar, .suppressedNBButton,
            .bibleVerse, .image, .button, .unknown("FutureWidget")
        ])
        XCTAssertEqual(page.sections[1].headerLevel, 2)
        XCTAssertEqual(page.sections[1].headerAttribute, "heading")
        XCTAssertEqual(page.sections[2].id, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(page.sections[3].style?.ordered, true)
        XCTAssertEqual(page.sections[3].children?.first?.value, "One")
        XCTAssertEqual(page.sections[6].source?.legacyProps?.reference, "Example 1:1")
        XCTAssertEqual(page.sections[7].src, "https://example.com/image.png")
        XCTAssertEqual(page.sections[7].alt, "Fixture image")
        XCTAssertEqual(page.sections[8].source?.legacyType, "Button")
    }

    func testTypedNavigationWinsAndLegacySlugRemainsSupported() throws {
        let pages = try JSONDecoder().decode([PageSummary].self, from: fixture("page-summaries"))
        let page = try JSONDecoder().decode(LocalizedPageContent.self, from: fixture("published-page"))
        XCTAssertEqual(page.sections[0].action?.type, "navigate")
        XCTAssertEqual(page.sections[0].action?.pageId, pages[0].publicId)
        XCTAssertEqual(PageContentLogic.targetPage(for: page.sections[0], allPages: pages)?.id, 1)
        XCTAssertEqual(PageContentLogic.targetPage(for: page.sections[5], allPages: pages)?.id, 2)
        XCTAssertNil(PageContentLogic.targetPage(for: page.sections[9], allPages: pages))
    }

    func testMissingRequiredEnvelopeAndSummaryFieldsFailDecoding() throws {
        let page = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("published-page")) as? [String: Any])
        for field in ["id", "title", "locale", "version", "sections"] {
            var invalid = page
            invalid.removeValue(forKey: field)
            let data = try JSONSerialization.data(withJSONObject: invalid)
            XCTAssertThrowsError(try JSONDecoder().decode(LocalizedPageContent.self, from: data), field)
        }
        let pages = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("page-summaries")) as? [[String: Any]])
        for field in ["id", "publicId", "slug", "title", "isPublished"] {
            var invalid = pages[0]
            invalid.removeValue(forKey: field)
            let data = try JSONSerialization.data(withJSONObject: [invalid])
            XCTAssertThrowsError(try JSONDecoder().decode([PageSummary].self, from: data), field)
        }
    }

    func testMalformedFieldsAndClientOnlySectionRequirementsFailDecoding() throws {
        let page = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("published-page")) as? [String: Any])
        for (field, value) in [
            ("id", "invalid-uuid"), ("version", "one"), ("sections", "not-an-array")
        ] {
            var invalid = page
            invalid[field] = value
            let data = try JSONSerialization.data(withJSONObject: invalid)
            XCTAssertThrowsError(try JSONDecoder().decode(LocalizedPageContent.self, from: data), field)
        }
        let invalidSections: [[[String: Any]]] = [
            [["value": "Missing client-required type"]],
            [["type": "button", "action": ["type": "navigate", "pageId": "invalid-uuid"]]],
            [["type": "text", "children": "not-an-array"]]
        ]
        for sections in invalidSections {
            var invalid = page
            invalid["sections"] = sections
            let data = try JSONSerialization.data(withJSONObject: invalid)
            XCTAssertThrowsError(try JSONDecoder().decode(LocalizedPageContent.self, from: data))
        }
    }

    func testMissingNavigationUUIDRetainsCurrentOptionalDecodingBehavior() throws {
        var page = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("published-page")) as? [String: Any])
        page["sections"] = [["type": "button", "action": ["type": "navigate"]]]
        let data = try JSONSerialization.data(withJSONObject: page)
        let decoded = try JSONDecoder().decode(LocalizedPageContent.self, from: data)
        XCTAssertNil(decoded.sections[0].action?.pageId)
        XCTAssertNil(PageContentLogic.targetPage(for: decoded.sections[0], allPages: []))
    }
}
