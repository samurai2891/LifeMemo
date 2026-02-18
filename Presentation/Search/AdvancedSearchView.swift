import SwiftUI

/// Advanced search view with FTS5-powered full-text search and date/filter controls.
struct AdvancedSearchView: View {

    // MARK: - Environment

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var coordinator: RecordingCoordinator

    // MARK: - State

    @State private var filter = SearchFilter()
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var showFilters = false
    @State private var currentPage = 0
    @State private var hasMore = false
    @State private var totalCount = 0
    @State private var availableTags: [TagInfo] = []
    @State private var availableFolders: [FolderInfo] = []

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if filter.hasActiveFilters {
                    activeFiltersBar
                }

                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty && !filter.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFilters) {
                filterSheet
            }
            .overlay { RecordingIndicatorOverlay() }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search transcripts...", text: $filter.query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { performSearch() }

                if !filter.query.isEmpty {
                    Button {
                        filter.query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                showFilters = true
            } label: {
                Image(systemName: filter.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
                )
                .font(.title3)
                .foregroundStyle(
                    filter.hasActiveFilters ? Color.accentColor : .secondary
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Active Filters Bar

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let from = filter.dateFrom {
                    filterChip("From: \(formatDate(from))") {
                        filter.dateFrom = nil
                        performSearch()
                    }
                }
                if let to = filter.dateTo {
                    filterChip("To: \(formatDate(to))") {
                        filter.dateTo = nil
                        performSearch()
                    }
                }
                if filter.highlightsOnly {
                    filterChip("Highlights Only") {
                        filter.highlightsOnly = false
                        performSearch()
                    }
                }
                if filter.hasAudio == true {
                    filterChip("Has Audio") {
                        filter.hasAudio = nil
                        performSearch()
                    }
                }
                if let tagName = filter.tagName {
                    filterChip("Tag: \(tagName)") {
                        filter.tagName = nil
                        performSearch()
                    }
                }
                if let folderName = filter.folderName {
                    filterChip("Folder: \(folderName)") {
                        filter.folderName = nil
                        performSearch()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func filterChip(
        _ text: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            if !results.isEmpty {
                Text("\(totalCount) results found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }

            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(result.sessionTitle)
                            .font(.subheadline.bold())

                        Spacer()

                        Text(formatMs(result.startMs))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(result.segmentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }

            if hasMore {
                Button("Load More") {
                    currentPage += 1
                    performSearch()
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.accentColor)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No results found")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Try different keywords or adjust your filters")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { filter.dateFrom ?? Date.distantPast },
                            set: { filter.dateFrom = $0 }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { filter.dateTo ?? Date() },
                            set: { filter.dateTo = $0 }
                        ),
                        displayedComponents: .date
                    )

                    if filter.dateFrom != nil || filter.dateTo != nil {
                        Button("Clear Dates") {
                            filter.dateFrom = nil
                            filter.dateTo = nil
                        }
                        .foregroundStyle(.red)
                    }
                }

                Section("Filters") {
                    Toggle("Highlights Only", isOn: $filter.highlightsOnly)

                    Toggle("Has Audio", isOn: Binding(
                        get: { filter.hasAudio ?? false },
                        set: { filter.hasAudio = $0 ? true : nil }
                    ))
                }

                Section("Tags & Folders") {
                    Picker("Tag", selection: $filter.tagName) {
                        Text("Any").tag(String?.none)
                        ForEach(availableTags) { tag in
                            Text(tag.name).tag(Optional(tag.name))
                        }
                    }

                    Picker("Folder", selection: $filter.folderName) {
                        Text("Any").tag(String?.none)
                        ForEach(availableFolders) { folder in
                            Text(folder.name).tag(Optional(folder.name))
                        }
                    }
                }

                Section("Sort") {
                    Picker("Sort Order", selection: $filter.sortOrder) {
                        ForEach(SearchFilter.SortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        showFilters = false
                        performSearch()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFilters = false
                    }
                }
            }
            .onAppear {
                availableTags = container.repository.fetchAllTags().map { $0.toInfo() }
                availableFolders = container.repository.fetchAllFolders().map { $0.toInfo() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func performSearch() {
        guard !filter.isEmpty else {
            results = []
            totalCount = 0
            hasMore = false
            return
        }

        isSearching = true
        let searchResults = container.advancedSearch.search(filter: filter, page: currentPage)
        results = currentPage == 0 ? searchResults.segments : results + searchResults.segments
        totalCount = searchResults.totalCount
        hasMore = searchResults.hasMore
        isSearching = false
    }

    // MARK: - Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private func formatMs(_ ms: Int64) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    AdvancedSearchView()
}
