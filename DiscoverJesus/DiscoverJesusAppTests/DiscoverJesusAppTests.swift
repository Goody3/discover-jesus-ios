//
//  DiscoverJesusAppTests.swift
//  DiscoverJesusAppTests
//
//  Created by Dalen Gudmunson on 11/6/26.
//

import XCTest
@testable import DiscoverJesus

final class DiscoverJesusAppTests: XCTestCase {
    func testDecodingCurrentComponentRolesAndUnknownComponent() throws {
        let payload = fixtureData(
            sections: [
                section(type: "button", value: "Start", actionPageId: destinationA.publicId.uuidString),
                section(type: "text", value: "Welcome", role: "heading", headingLevel: 1),
                section(type: "text", value: "Body copy"),
                section(
                    type: "stack",
                    role: "list",
                    label: "Items",
                    listStyle: "unordered",
                    children: [["type": "text", "value": "One"]]
                ),
                section(
                    type: "stack",
                    role: "navigation",
                    children: [[
                        "type": "button",
                        "role": "navigation-item",
                        "value": "Home",
                        "action": [
                            "type": "navigate",
                            "pageId": destinationA.publicId.uuidString
                        ]
                    ]]
                ),
                section(
                    type: "text",
                    value: "For God so loved...",
                    role: "scripture-reference",
                    reference: "John 3:16",
                    version: "niv"
                ),
                section(type: "image", src: "https://example.org/image.png", altText: "Image alt"),
                section(type: "MysteryType", value: "Unknown")
            ]
        )

        let content = try JSONDecoder().decode(LocalizedPageContent.self, from: payload)

        XCTAssertEqual(content.sections.count, 8)
        XCTAssertEqual(content.sections[1].role, "heading")
        XCTAssertEqual(content.sections[4].children?.first?.role, "navigation-item")
        XCTAssertEqual(content.sections[5].reference, "John 3:16")
        XCTAssertEqual(content.sections[6].altText, "Image alt")
    }

    func testDecodingMalformedPayloadThrows() {
        let malformed = Data("{\"id\":\"not-json\"".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(LocalizedPageContent.self, from: malformed))
    }

    func testDecodingEmptyPayloadThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(LocalizedPageContent.self, from: Data()))
    }

    func testRendererClassificationCoversSupportedTypesAndUnknownFallback() throws {
        let sections = try decodeSections([
            section(type: "button", value: "Tap"),
            section(type: "text", value: "H", role: "heading", headingLevel: 2),
            section(type: "text", value: "T"),
            section(type: "stack", role: "list"),
            section(type: "stack", role: "navigation"),
            section(type: "button", role: "navigation-item"),
            section(type: "text", value: "Verse", role: "scripture-reference"),
            section(type: "image", src: "https://example.org/image.png"),
            section(type: "Button", value: "Legacy type"),
            section(type: "MysteryType", value: "???")
        ])

        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[0], hasNavBarSection: false), .button)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[1], hasNavBarSection: false), .header)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[2], hasNavBarSection: false), .text)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[3], hasNavBarSection: false), .list)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[4], hasNavBarSection: false), .navBar)
        XCTAssertEqual(
            PageContentLogic.sectionKind(for: sections[5], hasNavBarSection: true),
            .suppressedNavigationItem
        )
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[6], hasNavBarSection: false), .bibleVerse)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[7], hasNavBarSection: false), .image)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[8], hasNavBarSection: false), .unknown("Button"))
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[9], hasNavBarSection: false), .unknown("MysteryType"))
    }

    func testNavigationResolutionRequiresUUIDPageId() throws {
        let byIdSection = try decodeSection(
            section(type: "button", value: "By ID", actionPageId: destinationA.publicId.uuidString)
        )
        let missingSection = try decodeSection(section(type: "button", value: "Missing"))

        XCTAssertEqual(PageContentLogic.targetPage(for: byIdSection, allPages: pages)?.id, destinationA.id)
        XCTAssertNil(PageContentLogic.targetPage(for: missingSection, allPages: pages))
    }

    func testLegacyMetadataDoesNotOverrideCurrentTypeOrResolveSlug() throws {
        let payload = Data(
            #"""
            {"type":"text","value":"Current text","source":{"legacyType":"Button","legacyProps":{"target":"about"}}}
            """#.utf8
        )
        let section = try JSONDecoder().decode(LocalizedPageSection.self, from: payload)

        XCTAssertEqual(PageContentLogic.sectionKind(for: section, hasNavBarSection: false), .text)
        XCTAssertNil(PageContentLogic.targetPage(for: section, allPages: pages))
    }

    func testErrorPathsFor4xx5xxMalformedAndEmptyPayloads() async {
        let requestURL = URL(string: "http://localhost:5187/api/content/pages/test?locale=en-US")!

        let status404Loader = PageContentLoader { _ in
            (self.fixtureData(sections: []), self.httpResponse(statusCode: 404, url: requestURL))
        }
        let status500Loader = PageContentLoader { _ in
            (self.fixtureData(sections: []), self.httpResponse(statusCode: 500, url: requestURL))
        }
        let malformedLoader = PageContentLoader { _ in
            (Data("{\"broken\":".utf8), self.httpResponse(statusCode: 200, url: requestURL))
        }
        let emptyLoader = PageContentLoader { _ in
            (Data(), self.httpResponse(statusCode: 200, url: requestURL))
        }

        let result404 = await status404Loader.load(from: requestURL)
        XCTAssertEqual(result404.errorMessage, "Backend returned an unexpected response (status 404).")
        XCTAssertEqual(result404.failedRequestURL, requestURL.absoluteString)

        let result500 = await status500Loader.load(from: requestURL)
        XCTAssertEqual(result500.errorMessage, "Backend returned an unexpected response (status 500).")
        XCTAssertEqual(result500.failedRequestURL, requestURL.absoluteString)

        let malformedResult = await malformedLoader.load(from: requestURL)
        XCTAssertNotNil(malformedResult.errorMessage)
        XCTAssertTrue(malformedResult.errorMessage?.hasPrefix("Unable to load page JSON:") == true)
        XCTAssertEqual(malformedResult.failedRequestURL, requestURL.absoluteString)

        let emptyResult = await emptyLoader.load(from: requestURL)
        XCTAssertNotNil(emptyResult.errorMessage)
        XCTAssertTrue(emptyResult.errorMessage?.hasPrefix("Unable to load page JSON:") == true)
        XCTAssertEqual(emptyResult.failedRequestURL, requestURL.absoluteString)
    }

    private var destinationA: PageSummary {
        PageSummary(
            publicId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            slug: "home",
            title: "Home"
        )
    }

    private var destinationB: PageSummary {
        PageSummary(
            publicId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            slug: "about",
            title: "About"
        )
    }

    private var pages: [PageSummary] { [destinationA, destinationB] }

    private func fixtureData(sections: [[String: Any]]) -> Data {
        let payload: [String: Any] = [
            "id": "33333333-3333-3333-3333-333333333333",
            "title": "Fixture Page",
            "locale": "en-US",
            "version": 1,
            "sections": sections
        ]

        return try! JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func section(
        type: String,
        value: String? = nil,
        actionPageId: String? = nil,
        role: String? = nil,
        label: String? = nil,
        headingLevel: Int? = nil,
        reference: String? = nil,
        version: String? = nil,
        src: String? = nil,
        altText: String? = nil,
        listStyle: String? = nil,
        children: [[String: Any]]? = nil
    ) -> [String: Any] {
        var dictionary: [String: Any] = ["type": type]
        if let value { dictionary["value"] = value }
        if let role { dictionary["role"] = role }
        if let label { dictionary["label"] = label }
        if let headingLevel { dictionary["headingLevel"] = headingLevel }
        if let reference { dictionary["reference"] = reference }
        if let version { dictionary["version"] = version }
        if let src { dictionary["src"] = src }
        if let altText { dictionary["altText"] = altText }
        if let children { dictionary["children"] = children }
        if let listStyle { dictionary["style"] = ["listStyle": listStyle] }

        if let actionPageId {
            dictionary["action"] = ["type": "navigate", "pageId": actionPageId]
        }

        return dictionary
    }

    private func decodeSections(_ sections: [[String: Any]]) throws -> [LocalizedPageSection] {
        let data = fixtureData(sections: sections)
        return try JSONDecoder().decode(LocalizedPageContent.self, from: data).sections
    }

    private func decodeSection(_ section: [String: Any]) throws -> LocalizedPageSection {
        try XCTUnwrap(decodeSections([section]).first)
    }

    private func httpResponse(statusCode: Int, url: URL) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}