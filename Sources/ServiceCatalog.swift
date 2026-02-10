// ServiceCatalog.swift
// Browsable catalog of popular status pages with search and one-click add.

import SwiftUI

// MARK: - Catalog Parsing

func parseCatalog() -> [CatalogEntry] {
    kServiceCatalog
        .split(separator: "\n", omittingEmptySubsequences: true)
        .compactMap { line -> CatalogEntry? in
            let raw = String(line).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            let parts = raw.split(separator: "\t")
            guard parts.count == 3 else { return nil }
            return CatalogEntry(
                name: String(parts[0]),
                url: String(parts[1]),
                category: String(parts[2])
            )
        }
}

// MARK: - Service Catalog View

struct ServiceCatalogView: View {
    @ObservedObject var service: StatusService
    let onBack: () -> Void
    @State private var searchText = ""

    private var catalog: [CatalogEntry] { parseCatalog() }

    private var filteredEntries: [CatalogEntry] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return catalog
        }
        let query = searchText.lowercased()
        return catalog.filter {
            $0.name.lowercased().contains(query) || $0.category.lowercased().contains(query)
        }
    }

    private var groupedEntries: [(category: String, entries: [CatalogEntry])] {
        var groups: [String: [CatalogEntry]] = [:]
        for entry in filteredEntries {
            groups[entry.category, default: []].append(entry)
        }
        return groups.keys.sorted().map { (category: $0, entries: groups[$0]!) }
    }

    private var existingURLs: Set<String> {
        Set(service.sources.map { $0.baseURL })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            catalogHeader
            Divider().opacity(0.5)

            TextField("Search services\u{2026}", text: $searchText)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider().opacity(0.3)

            ScrollView {
                if filteredEntries.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        Text("No services match \"\(searchText)\"")
                            .font(Design.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedEntries, id: \.category) { group in
                            Text(group.category)
                                .font(Design.Typography.captionSemibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 4)

                            ForEach(group.entries) { entry in
                                catalogRow(entry)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().opacity(0.5)
            catalogFooter
        }
    }

    private var catalogHeader: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Design.Typography.body)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back (Esc)")
            .accessibilityLabel("Back to source list")

            Image(systemName: "list.star")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            Text("Service Catalog")
                .font(Design.Typography.bodyMedium)
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func catalogRow(_ entry: CatalogEntry) -> some View {
        let isAdded = existingURLs.contains(entry.url) || existingURLs.contains(entry.url + "/")
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(Design.Typography.captionMedium)
                    .lineLimit(1)
                Text(entry.url)
                    .font(Design.Typography.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .font(Design.Typography.body)
                    .foregroundStyle(.green)
            } else {
                Button {
                    withAnimation(Design.Timing.expand) {
                        service.addSource(name: entry.name, baseURL: entry.url, group: entry.category)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(Design.Typography.body)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Add \(entry.name)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.category)\(isAdded ? ", already added" : "")")
        .accessibilityHint(isAdded ? "" : "Double tap to add to your sources")
    }

    private var catalogFooter: some View {
        HStack {
            Text("\(filteredEntries.count) service\(filteredEntries.count == 1 ? "" : "s")")
                .font(Design.Typography.micro)
                .foregroundStyle(.quaternary)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(Design.Typography.micro)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Quit StatusBar")
            .accessibilityLabel("Quit StatusBar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
