//
//  DiscoverJesusAppTests.swift
//  DiscoverJesusAppTests
//
//  Created by Dalen Gudmunson on 11/6/26.
//

import XCTest
@testable import DiscoverJesus

final class DiscoverJesusAppTests: XCTestCase {
    func testDecodingSupportedComponentTypesAndLegacyFallback() throws {
        let payload = fixtureData(
            sections: [
                section(type: "Button", value: "Start", actionPageId: destinationA.publicId.uuidString),
                section(type: "Header", value: "Welcome", level: 1),
                section(type: "Text", value: "Body copy"),
                section(type: "List", children: [["type": "Text", "value": "One"]]),
                section(type: "NavBar", children: [["type": "Text", "value": "Home"]]),
                section(type: "NBButton", value: "Home", target: "home"),
                section(type: "BibleVerse", value: "For God so loved...", reference: "John 3:16", version: "niv"),
                section(type: "Image", src: "example.com/image.png", alt: "Image alt"),
                section(type: "Text", value: "Legacy button", legacyType: "Button")
            ]
        )

        let content = try JSONDecoder().decode(LocalizedPageContent.self, from: payload)

        XCTAssertEqual(content.sections.count, 9)
        XCTAssertEqual(content.sections[8].source?.legacyType, "Button")
        XCTAssertEqual(content.sections[4].type, "NavBar")
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
            section(type: "Button", value: "Tap"),
            section(type: "Header", value: "H"),
            section(type: "Text", value: "T"),
            section(type: "List", children: [["type": "Text", "value": "One"]]),
            section(type: "NavBar", children: [["type": "Text", "value": "Home"]]),
            section(type: "NBButton", value: "Home"),
            section(type: "BibleVerse", value: "Verse"),
            section(type: "Image", src: "example.com/image.png"),
            section(type: "Text", value: "Legacy", legacyType: "Button"),
            section(type: "MysteryType", value: "???")
        ])

        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[0], hasNavBarSection: false), .button)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[1], hasNavBarSection: false), .header)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[2], hasNavBarSection: false), .text)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[3], hasNavBarSection: false), .list)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[4], hasNavBarSection: false), .navBar)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[5], hasNavBarSection: true), .suppressedNBButton)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[6], hasNavBarSection: false), .bibleVerse)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[7], hasNavBarSection: false), .image)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[8], hasNavBarSection: false), .button)
        XCTAssertEqual(PageContentLogic.sectionKind(for: sections[9], hasNavBarSection: false), .unknown("MysteryType"))
    }

    func testNavigationResolutionPrefersPageIdThenSlugFallbackAndMissingTarget() throws {
        let byIdSection = try decodeSection(section(type: "Button", value: "By ID", actionPageId: destinationA.publicId.uuidString, target: "other"))
        let bySlugSection = try decodeSection(section(type: "Button", value: "By Slug", target: destinationB.slug.uppercased()))
        let missingSection = try decodeSection(section(type: "Button", value: "Missing", target: "not-found"))

        XCTAssertEqual(PageContentLogic.targetPage(for: byIdSection, allPages: pages)?.id, destinationA.id)
        XCTAssertEqual(PageContentLogic.targetPage(for: bySlugSection, allPages: pages)?.id, destinationB.id)
        XCTAssertNil(PageContentLogic.targetPage(for: missingSection, allPages: pages))
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
            id: 1,
            publicId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            slug: "home",
            title: "Home",
            isPublished: true
        )
    }

    private var destinationB: PageSummary {
        PageSummary(
            id: 2,
            publicId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            slug: "about",
            title: "About",
            isPublished: true
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
        legacyType: String? = nil,
        target: String? = nil,
        level: Int? = nil,
        reference: String? = nil,
        version: String? = nil,
        src: String? = nil,
        alt: String? = nil,
        children: [[String: Any]]? = nil
    ) -> [String: Any] {
        var dictionary: [String: Any] = ["type": type]
        if let value { dictionary["value"] = value }
        if let level { dictionary["level"] = level }
        if let src { dictionary["src"] = src }
        if let alt { dictionary["alt"] = alt }
        if let children { dictionary["children"] = children }

        if let actionPageId {
            dictionary["action"] = ["type": "navigate", "pageId": actionPageId]
        }

        var legacyProps: [String: Any] = [:]
        if let target { legacyProps["target"] = target }
        if let reference { legacyProps["reference"] = reference }
        if let version { legacyProps["version"] = version }
        if !legacyProps.isEmpty || legacyType != nil {
            dictionary["source"] = [
                "legacyType": legacyType as Any,
                "legacyProps": legacyProps
            ]
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