import SwiftUI
import Combine

struct PageSummary: Decodable, Identifiable, Hashable {
    let publicId: UUID
    let slug: String
    let title: String

    var id: UUID { publicId }
}

private enum ReaderAPI {
    static let baseURL = URL(string: "http://localhost:5187/api/content/pages")!
    static let locale = URLQueryItem(name: "locale", value: "en-US")

    static func pagesURL() -> URL {
        baseURL.appending(queryItems: [locale])
    }

    static func pageURL(_ id: UUID) -> URL {
        baseURL.appending(path: id.uuidString).appending(queryItems: [locale])
    }
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
    let role: String?
    let label: String?
    let action: LocalizedPageSectionAction?
    let headingLevel: Int?
    let reference: String?
    let version: String?
    let style: LocalizedPageSectionStyle?
    let children: [LocalizedPageSection]?
    let src: String?
    let altText: String?

    // Use source component id when present, otherwise fall back to a synthetic id.
    var id: String {
        sourceComponentId ?? "\(type)-\(value ?? "")"
    }

    private let sourceComponentId: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case role
        case label
        case action
        case sourceComponentId
        case headingLevel
        case reference
        case version
        case style
        case children
        case src
        case altText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        action = try container.decodeIfPresent(LocalizedPageSectionAction.self, forKey: .action)
        sourceComponentId = try container.decodeIfPresent(String.self, forKey: .sourceComponentId)
        headingLevel = try container.decodeIfPresent(Int.self, forKey: .headingLevel)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        style = try container.decodeIfPresent(LocalizedPageSectionStyle.self, forKey: .style)
        children = try container.decodeIfPresent([LocalizedPageSection].self, forKey: .children)
        src = try container.decodeIfPresent(String.self, forKey: .src)
        altText = try container.decodeIfPresent(String.self, forKey: .altText)
    }
}

struct LocalizedPageSectionStyle: Decodable {
    let listStyle: String?
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

    func loadPages() async {
        isLoading = true
        errorMessage = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: ReaderAPI.pagesURL())
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
    let loader = PageContentLoader()

    @State private var isLoading = false
    @State private var jsonText = ""
    @State private var renderedPage: LocalizedPageContent?
    @State private var errorMessage: String?
    @State private var failedRequestURL: String?

    private var endpoint: URL {
        ReaderAPI.pageURL(page.publicId)
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
        let hasNavBarSection = (renderedPage?.sections ?? []).contains {
            PageContentLogic.sectionKind(for: $0, hasNavBarSection: false) == .navBar
        }
        let sectionKind = PageContentLogic.sectionKind(for: section, hasNavBarSection: hasNavBarSection)

        if sectionKind == .navBar {
            navBarView(for: section)
        } else if sectionKind == .suppressedNavigationItem {
            EmptyView()
        } else if sectionKind == .list {
            listView(for: section)
        } else if sectionKind == .button {
            let buttonText = section.value ?? "Button"

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
        } else if sectionKind == .header {
            let style = headerStyle(for: section)
            Text(sectionDisplayText(section, fallback: "(empty header)"))
                .font(style.font)
                .fontWeight(style.weight)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if sectionKind == .bibleVerse {
            bibleVerseView(for: section)
        } else if sectionKind == .image {
            imageView(for: section)
        } else if sectionKind == .text {
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
        let altText = (section.altText ?? "")
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
        let raw = section.src
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
        (section.children ?? [])
            .filter { ($0.role ?? "").caseInsensitiveCompare("navigation-item") == .orderedSame }
            .map { child in
                let rawLabel = child.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let label = rawLabel.isEmpty ? "Button" : rawLabel
                return (label, targetPage(for: child))
            }
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
        let reference = section.reference?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = section.version?.trimmingCharacters(in: .whitespacesAndNewlines)

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
            .filter { $0.type.lowercased() == "text" }
            .map { ($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ordered = section.style?.listStyle == "ordered"

        VStack(alignment: .leading, spacing: 6) {
            if let title = section.label?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
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
        let trimmed = section.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func headerStyle(for section: LocalizedPageSection) -> (font: Font, weight: Font.Weight) {
        switch section.headingLevel {
        case 1:
            return (.largeTitle, .bold)
        case 3:
            return (.title3, .semibold)
        default:
            return (.title2, .semibold)
        }
    }

    private func targetPage(for section: LocalizedPageSection) -> PageSummary? {
        PageContentLogic.targetPage(for: section, allPages: allPages)
    }

    private func loadPageJSON() async {
        isLoading = true
        errorMessage = nil
        failedRequestURL = nil
        renderedPage = nil

        defer { isLoading = false }

        let result = await loader.load(from: endpoint)
        jsonText = result.jsonText
        renderedPage = result.renderedPage
        errorMessage = result.errorMessage
        failedRequestURL = result.failedRequestURL
    }
}

#Preview {
    ContentView()
}