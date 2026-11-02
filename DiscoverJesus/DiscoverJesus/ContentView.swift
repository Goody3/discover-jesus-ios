import SwiftUI
import Combine

struct PageSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let publicId: UUID
    let slug: String
    let title: String
    let isPublished: Bool
}

struct LocalizedPageContent: Decodable {
    let id: UUID
    let title: String
    let locale: String
    let version: Int
    let sections: [LocalizedPageSection]
}

struct LocalizedPageSection: Decodable, Identifiable {
    let type: String
    let value: String?
    let source: LocalizedPageSectionSource?
    let action: LocalizedPageSectionAction?
    let headerLevel: Int?
    let headerAttribute: String?
    let style: LocalizedPageSectionStyle?
    let children: [LocalizedPageSectionChild]?
    let src: String?
    let alt: String?

    // Use source component id when present, otherwise fall back to a synthetic id.
    var id: String {
        sourceComponentId ?? "\(type)-\(value ?? "")"
    }

    private let sourceComponentId: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case source
        case action
        case sourceComponentId
        case headerLevel
        case level
        case attribute
        case style
        case children
        case src
        case alt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        source = try container.decodeIfPresent(LocalizedPageSectionSource.self, forKey: .source)
        action = try container.decodeIfPresent(LocalizedPageSectionAction.self, forKey: .action)
        sourceComponentId = try container.decodeIfPresent(String.self, forKey: .sourceComponentId)
        headerLevel = try container.decodeIfPresent(Int.self, forKey: .headerLevel)
            ?? container.decodeIfPresent(Int.self, forKey: .level)
        headerAttribute = try container.decodeIfPresent(String.self, forKey: .attribute)
        style = try container.decodeIfPresent(LocalizedPageSectionStyle.self, forKey: .style)
        children = try container.decodeIfPresent([LocalizedPageSectionChild].self, forKey: .children)
        src = try container.decodeIfPresent(String.self, forKey: .src)
        alt = try container.decodeIfPresent(String.self, forKey: .alt)
    }
}

struct LocalizedPageSectionStyle: Decodable {
    let role: String?
    let ordered: Bool?
}

struct LocalizedPageSectionChild: Decodable {
    let type: String?
    let value: String?
}

struct LocalizedPageSectionSource: Decodable {
    let legacyType: String?
    let legacyProps: LegacyProps?
}

struct LegacyProps: Decodable {
    let text: String?
    let target: String?
    let headerLevel: Int?
    let headerAttribute: String?
    let reference: String?
    let version: String?
    let url: String?

    private enum CodingKeys: String, CodingKey {
        case text
        case target
        case headerLevel
        case level
        case attribute
        case reference
        case version
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        headerLevel = try container.decodeIfPresent(Int.self, forKey: .headerLevel)
            ?? container.decodeIfPresent(Int.self, forKey: .level)
        headerAttribute = try container.decodeIfPresent(String.self, forKey: .attribute)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}

struct LocalizedPageSectionAction: Decodable {
    let type: String?
    let pageId: UUID?
}

@MainActor
final class PagesViewModel: ObservableObject {
    @Published var pages: [PageSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let endpoint = URL(string: "http://localhost:5187/api/pages")!

    func loadPages() async {
        isLoading = true
        errorMessage = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode else {
                errorMessage = "Backend returned an unexpected response."
                isLoading = false
                return
            }

            pages = try JSONDecoder().decode([PageSummary].self, from: data)
        } catch {
            errorMessage = "Unable to load pages: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

struct ContentView: View {
    @StateObject private var viewModel = PagesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.pages.isEmpty {
                    ProgressView("Loading pages...")
                } else if let errorMessage = viewModel.errorMessage, viewModel.pages.isEmpty {
                    ContentUnavailableView(
                        "Could not load pages",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    List(viewModel.pages) { page in
                        NavigationLink {
                            PageJSONView(page: page, allPages: viewModel.pages)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.title)
                                    .font(.headline)
                                Text("/\(page.slug)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if !page.isPublished {
                                    Text("Draft")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Discover Jesus")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reload") {
                        Task { await viewModel.loadPages() }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.loadPages()
            }
            .refreshable {
                await viewModel.loadPages()
            }
        }
    }
}

struct PageJSONView: View {
    let page: PageSummary
    let allPages: [PageSummary]

    @State private var isLoading = false
    @State private var jsonText = ""
    @State private var renderedPage: LocalizedPageContent?
    @State private var errorMessage: String?
    @State private var failedRequestURL: String?

    private let locale = "en-US"

    private var endpoint: URL {
        URL(string: "http://localhost:5187/api/content/pages/\(page.publicId.uuidString)?locale=\(locale)")!
    }

    var body: some View {
        Group {
            if isLoading && jsonText.isEmpty {
                ProgressView("Loading page JSON...")
            } else if let errorMessage, jsonText.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Could not load page JSON", systemImage: "exclamationmark.triangle")
                        .font(.headline)

                    Text(errorMessage)
                        .foregroundStyle(.secondary)

                    if let failedRequestURL {
                        Text("Failed API call")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ScrollView(.horizontal) {
                            Text(failedRequestURL)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button("Copy API URL") {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = failedRequestURL
                            #endif
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                VStack(spacing: 0) {
                    topRenderedView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Divider()

                    rawJSONView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reload") {
                    Task { await loadPageJSON() }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadPageJSON()
        }
    }

    private var topRenderedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rendered Content")
                    .font(.headline)

                if let renderedPage {
                    if renderedPage.sections.isEmpty {
                        Text("No sections found in this page definition.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(renderedPage.sections) { section in
                            renderedSectionView(section)
                        }
                    }
                } else {
                    Text("No renderable content available.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var rawJSONView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Raw JSON")
                    .font(.headline)

                Text(jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func renderedSectionView(_ section: LocalizedPageSection) -> some View {
        let normalizedType = section.type.lowercased()
        let normalizedLegacyType = section.source?.legacyType?.lowercased()
        let effectiveType = normalizedLegacyType ?? normalizedType

        if isNavBarSection(section, effectiveType: effectiveType) {
            navBarView(for: section)
        } else if shouldSuppressStandaloneNBButton(effectiveType: effectiveType) {
            EmptyView()
        } else if isListSection(section, effectiveType: effectiveType) {
            listView(for: section)
        } else if effectiveType == "button" || effectiveType == "nbbutton" {
            let buttonText = section.source?.legacyProps?.text ?? section.value ?? "Button"

            if let destination = targetPage(for: section) {
                NavigationLink {
                    PageJSONView(page: destination, allPages: allPages)
                } label: {
                    Text(buttonText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(buttonText) { }
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
        } else if effectiveType == "header" {
            let style = headerStyle(for: section)
            Text(sectionDisplayText(section, fallback: "(empty header)"))
                .font(style.font)
                .fontWeight(style.weight)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if effectiveType == "bibleverse" {
            bibleVerseView(for: section)
        } else if effectiveType == "media" || normalizedType == "image" || effectiveType == "image" {
            imageView(for: section)
        } else if effectiveType == "text" {
            Text(sectionDisplayText(section, fallback: "(empty text)"))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("{\(section.type)}")
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func imageView(for section: LocalizedPageSection) -> some View {
        let url = imageURL(for: section)
        let altText = (section.alt ?? section.source?.legacyProps?.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 8) {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .failure:
                        Text("(image failed to load)")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(.thinMaterial)
                    @unknown default:
                        EmptyView()
                    }
                }

                if !altText.isEmpty {
                    Text(altText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("(image url missing)")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageURL(for section: LocalizedPageSection) -> URL? {
        let raw = section.src ?? section.source?.legacyProps?.url
        guard let raw else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }

        return URL(string: "https://\(trimmed)")
    }

    private func navBarView(for section: LocalizedPageSection) -> some View {
        let items = navBarItems(for: section)

        return VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("(empty navigation bar)")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        if let destination = item.destination {
                            NavigationLink {
                                PageJSONView(page: destination, allPages: allPages)
                            } label: {
                                Text(item.label)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(item.label) { }
                                .buttonStyle(.bordered)
                                .disabled(true)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func navBarItems(for section: LocalizedPageSection) -> [(label: String, destination: PageSummary?)] {
        var availableNBButtons = (renderedPage?.sections ?? []).filter {
            $0.source?.legacyType?.caseInsensitiveCompare("NBButton") == .orderedSame
        }

        var items: [(label: String, destination: PageSummary?)] = []

        let orderedLabels = (section.children ?? [])
            .compactMap { child -> String? in
                let trimmed = (child.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

        for label in orderedLabels {
            if let index = availableNBButtons.firstIndex(where: {
                buttonLabel(for: $0).caseInsensitiveCompare(label) == .orderedSame
            }) {
                let match = availableNBButtons.remove(at: index)
                items.append((buttonLabel(for: match), targetPage(for: match)))
            } else {
                items.append((label, nil))
            }
        }

        // Include any remaining NBButtons not listed in children.
        for buttonSection in availableNBButtons {
            items.append((buttonLabel(for: buttonSection), targetPage(for: buttonSection)))
        }

        return items
    }

    private func buttonLabel(for section: LocalizedPageSection) -> String {
        let raw = section.source?.legacyProps?.text ?? section.value ?? "Button"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Button" : trimmed
    }

    private func isNavBarSection(_ section: LocalizedPageSection, effectiveType: String) -> Bool {
        if section.style?.role?.caseInsensitiveCompare("navigation") == .orderedSame {
            return true
        }

        return effectiveType == "navbar"
    }

    private func shouldSuppressStandaloneNBButton(effectiveType: String) -> Bool {
        effectiveType == "nbbutton" && renderedPage?.sections.contains(where: {
            ($0.source?.legacyType?.caseInsensitiveCompare("NavBar") == .orderedSame)
                || ($0.style?.role?.caseInsensitiveCompare("navigation") == .orderedSame)
        }) == true
    }

    private func bibleVerseView(for section: LocalizedPageSection) -> some View {
        let verseText = sectionDisplayText(section, fallback: "(verse text unavailable)")
        let referenceText = verseReferenceText(for: section)

        return VStack(alignment: .leading, spacing: 10) {
            Text(verseText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let referenceText {
                Text(referenceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // Roughly 10% side margins on common iPhone widths.
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verseReferenceText(for section: LocalizedPageSection) -> String? {
        let reference = section.source?.legacyProps?.reference?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = section.source?.legacyProps?.version?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let reference, !reference.isEmpty else {
            return nil
        }

        if let version, !version.isEmpty {
            return "\(reference) (\(version.uppercased()))"
        }

        return reference
    }

    @ViewBuilder
    private func listView(for section: LocalizedPageSection) -> some View {
        let items = (section.children ?? [])
            .filter { ($0.type ?? "text").lowercased() == "text" }
            .map { ($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ordered = section.style?.ordered ?? isLegacyOrderedList(section)

        VStack(alignment: .leading, spacing: 6) {
            if let title = section.source?.legacyProps?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

            if items.isEmpty {
                Text("(empty list)")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .frame(width: 24, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionDisplayText(_ section: LocalizedPageSection, fallback: String) -> String {
        let raw = section.source?.legacyProps?.text ?? section.value
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func headerStyle(for section: LocalizedPageSection) -> (font: Font, weight: Font.Weight) {
        let rawAttribute = section.headerAttribute ?? section.source?.legacyProps?.headerAttribute
        let attribute = rawAttribute?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        switch attribute {
        case "H1":
            return (.largeTitle, .bold)
        case "H3":
            return (.title3, .semibold)
        case "H2":
            return (.title2, .semibold)
        default:
            let level = section.headerLevel ?? section.source?.legacyProps?.headerLevel
            switch level {
            case 1:
                return (.largeTitle, .bold)
            case 3:
                return (.title3, .semibold)
            default:
                return (.title2, .semibold)
            }
        }
    }

    private func isListSection(_ section: LocalizedPageSection, effectiveType: String) -> Bool {
        if section.style?.role?.caseInsensitiveCompare("list") == .orderedSame {
            return true
        }

        return effectiveType == "list"
    }

    private func isLegacyOrderedList(_ section: LocalizedPageSection) -> Bool {
        let raw = section.source?.legacyProps?.headerAttribute ?? section.headerAttribute
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ol"
    }

    private func targetPage(for section: LocalizedPageSection) -> PageSummary? {
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

    private func loadPageJSON() async {
        isLoading = true
        errorMessage = nil
        failedRequestURL = nil
        renderedPage = nil

        defer { isLoading = false }

        do {
            let requestURL = endpoint
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                failedRequestURL = requestURL.absoluteString
                errorMessage = "Backend returned an unexpected response (status \(statusCode))."
                return
            }

            let object = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            jsonText = String(decoding: prettyData, as: UTF8.self)

            renderedPage = try JSONDecoder().decode(LocalizedPageContent.self, from: data)
        } catch {
            failedRequestURL = endpoint.absoluteString
            errorMessage = "Unable to load page JSON: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}