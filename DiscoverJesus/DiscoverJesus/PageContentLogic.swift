import Foundation

enum RenderSectionKind: Equatable {
    case navBar
    case suppressedNBButton
    case list
    case button
    case header
    case bibleVerse
    case image
    case text
    case unknown(String)
}

struct ParsedPagePayload {
    let jsonText: String
    let renderedPage: LocalizedPageContent
}

struct PageContentLoadResult {
    var jsonText: String = ""
    var renderedPage: LocalizedPageContent?
    var errorMessage: String?
    var failedRequestURL: String?
}

struct PageContentLogic {
    static func sectionKind(for section: LocalizedPageSection, hasNavBarSection: Bool) -> RenderSectionKind {
        let normalizedType = section.type.lowercased()
        let normalizedLegacyType = section.source?.legacyType?.lowercased()
        let effectiveType = normalizedLegacyType ?? normalizedType

        if section.style?.role?.caseInsensitiveCompare("navigation") == .orderedSame || effectiveType == "navbar" {
            return .navBar
        }

        if effectiveType == "nbbutton" && hasNavBarSection {
            return .suppressedNBButton
        }

        if section.style?.role?.caseInsensitiveCompare("list") == .orderedSame || effectiveType == "list" {
            return .list
        }

        if effectiveType == "button" || effectiveType == "nbbutton" {
            return .button
        }

        if effectiveType == "header" {
            return .header
        }

        if effectiveType == "bibleverse" {
            return .bibleVerse
        }

        if effectiveType == "media" || normalizedType == "image" || effectiveType == "image" {
            return .image
        }

        if effectiveType == "text" {
            return .text
        }

        return .unknown(section.type)
    }

    static func targetPage(for section: LocalizedPageSection, allPages: [PageSummary]) -> PageSummary? {
        if let pageId = section.action?.pageId,
           let byId = allPages.first(where: { $0.publicId == pageId }) {
            return byId
        }

        if let targetSlug = section.source?.legacyProps?.target,
           let bySlug = allPages.first(where: { $0.slug.caseInsensitiveCompare(targetSlug) == .orderedSame }) {
            return bySlug
        }

        return nil
    }

    static func parsePagePayload(data: Data) throws -> ParsedPagePayload {
        let object = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let renderedPage = try JSONDecoder().decode(LocalizedPageContent.self, from: data)

        return ParsedPagePayload(
            jsonText: String(decoding: prettyData, as: UTF8.self),
            renderedPage: renderedPage
        )
    }

    static func unexpectedResponseMessage(statusCode: Int) -> String {
        "Backend returned an unexpected response (status \(statusCode))."
    }

    static func loadFailureMessage(error: Error) -> String {
        "Unable to load page JSON: \(error.localizedDescription)"
    }
}

struct PageContentLoader {
    private let dataProvider: (URL) async throws -> (Data, URLResponse)

    init(session: URLSession = URLSession.shared) {
        self.dataProvider = { url in
            try await session.data(from: url)
        }
    }

    init(dataProvider: @escaping (URL) async throws -> (Data, URLResponse)) {
        self.dataProvider = dataProvider
    }

    func load(from requestURL: URL) async -> PageContentLoadResult {
        do {
            let (data, response) = try await dataProvider(requestURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                return PageContentLoadResult(
                    errorMessage: PageContentLogic.unexpectedResponseMessage(statusCode: statusCode),
                    failedRequestURL: requestURL.absoluteString
                )
            }

            let parsed = try PageContentLogic.parsePagePayload(data: data)
            return PageContentLoadResult(jsonText: parsed.jsonText, renderedPage: parsed.renderedPage)
        } catch {
            return PageContentLoadResult(
                errorMessage: PageContentLogic.loadFailureMessage(error: error),
                failedRequestURL: requestURL.absoluteString
            )
        }
    }
}
