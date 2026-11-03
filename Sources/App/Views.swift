import SwiftUI
import AppKit

enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(for path: String) -> Image {
        if let hit = cache[path] { return Image(nsImage: hit) }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache[path] = img
        return Image(nsImage: img)
    }
}

/// "‹ Page 2 of 4 ›"
struct PagerView: View {
    @Binding var page: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Button { page -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(page <= 0)
            Text("Page \(min(page, max(pageCount - 1, 0)) + 1) of \(max(pageCount, 1))")
                .font(.caption).monospacedDigit()
            Button { page += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(page >= pageCount - 1)
        }
        .buttonStyle(.borderless)
    }
}

private func pageCount(_ items: Int, _ size: Int) -> Int { max((items + size - 1) / size, 1) }

// MARK: Settings

struct SettingsView: View {
    @ObservedObject var model: FirewallModel
    @State private var allowedPage = 0
    @State private var blockedPage = 0
    private let pageSize = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(model.status == .unreachable ? Color.red : Color.green).frame(width: 8, height: 8)
                Text(model.statusText).font(.callout)
                Spacer()
            }
            .padding(12)
            Divider()
            if model.rules.isEmpty {
                ContentUnavailableView("No apps yet", systemImage: "shield",
                    description: Text("Apps appear here after you allow or block them."))
            } else {
                List {
                    section("Allowed", .allow, page: $allowedPage)
                    section("Blocked", .block, page: $blockedPage)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    @ViewBuilder
    private func section(_ title: String, _ action: RuleAction, page: Binding<Int>) -> some View {
        let items = model.rules.filter { $0.action == action }
        let pages = pageCount(items.count, pageSize)
        let current = min(page.wrappedValue, pages - 1)
        let visible = items.dropFirst(current * pageSize).prefix(pageSize)

        Section("\(title) (\(items.count))") {
            if items.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
            ForEach(Array(visible)) { rule in
                HStack(spacing: 10) {
                    IconCache.icon(for: rule.key).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading) {
                        Text(rule.name)
                        Text(rule.key).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if action == .allow {
                        Button("Block") { model.set(rule, to: .block) }
                    } else {
                        Button("Unblock") { model.set(rule, to: .allow) }
                    }
                    Button { model.forget(rule) } label: { Image(systemName: "trash") }
                        .help("Forget this app. You will be asked again next time it connects.")
                }
                .padding(.vertical, 2)
            }
            if pages > 1 {
                HStack { Spacer(); PagerView(page: page, pageCount: pages); Spacer() }
            }
        }
        .onChange(of: pages) { _, new in if page.wrappedValue >= new { page.wrappedValue = new - 1 } }
    }
}

// MARK: History

struct HistoryView: View {
    @ObservedObject var model: FirewallModel
    @State private var sortOrder = [KeyPathComparator(\ConnectionRecord.timestamp, order: .reverse)]
    @State private var search = ""
    @State private var page = 0
    @State private var selection = Set<ConnectionRecord.ID>()
    private let pageSize = 10

    private var filtered: [ConnectionRecord] {
        _ = model.resolveTick   // redraw when host names arrive
        let all = model.history.sorted(using: sortOrder)
        guard !search.isEmpty else { return all }
        return all.filter {
            [$0.appName, $0.kind, $0.verdict,
             model.display($0.source, isSource: true), model.display($0.destination, isSource: false)]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        let rows = filtered
        let pages = pageCount(rows.count, pageSize)
        let current = min(page, pages - 1)
        let visible = Array(rows.dropFirst(current * pageSize).prefix(pageSize))

        VStack(spacing: 0) {
            Table(visible, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("App", value: \.appName) { r in
                    HStack {
                        IconCache.icon(for: r.appKey).resizable().frame(width: 16, height: 16)
                        Text(r.appName)
                    }
                }.width(min: 110, ideal: 150)
                TableColumn("Type", value: \.kind) { Text($0.kind) }.width(min: 50, ideal: 60)
                TableColumn("Direction", value: \.direction) { Text($0.direction) }.width(min: 65, ideal: 75)
                TableColumn("Date & Time", value: \.timestamp) { r in
                    Text(r.timestamp.formatted(date: .abbreviated, time: .standard))
                }.width(min: 150, ideal: 170)
                TableColumn("Source", value: \.source) { r in
                    Text(model.display(r.source, isSource: true)).textSelection(.enabled)
                }.width(min: 130, ideal: 170)
                TableColumn("Destination", value: \.destination) { r in
                    Text(model.display(r.destination, isSource: false)).textSelection(.enabled)
                }.width(min: 160, ideal: 230)
                TableColumn("Result", value: \.verdict) { r in
                    Text(r.verdict).foregroundStyle(r.verdict == "Blocked" ? Color.red : Color.green)
                }.width(min: 60, ideal: 70)
            }
            .contextMenu(forSelectionType: ConnectionRecord.ID.self) { ids in
                if let record = model.history.first(where: { ids.contains($0.id) }) {
                    Button("Open App Location in Finder") { reveal(record) }
                        .disabled(!FileManager.default.fileExists(atPath: record.appKey))
                }
            }
            Divider()
            ZStack {
                HStack {
                    Text("Latest \(model.history.count) of max 100 connections")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                PagerView(page: $page, pageCount: pages)
            }
            .padding(8)
        }
        .searchable(text: $search)
        .onChange(of: search) { _, _ in page = 0 }
        .onChange(of: pages) { _, new in if page >= new { page = new - 1 } }
        .frame(minWidth: 900, minHeight: 440)
    }

    private func reveal(_ record: ConnectionRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.appKey)])
    }
}

// MARK: About

struct AboutView: View {
    private var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "iAnish Firewall"
    }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 44)).foregroundStyle(.tint)
            Text(name).font(.title2.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 260)
    }
}
