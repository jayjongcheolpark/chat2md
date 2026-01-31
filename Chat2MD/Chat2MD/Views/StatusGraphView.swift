import SwiftUI

struct StatusGraphView: View {
    let entries: [SyncHistoryEntry]
    @State private var hoveredIndex: Int?

    private let barCount = 48
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let barWidth = (geometry.size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let entry = entryForBar(at: index)
                    Rectangle()
                        .fill(colorForEntry(entry))
                        .frame(width: max(barWidth, 2))
                        .cornerRadius(2)
                        .opacity(hoveredIndex == index ? 0.7 : 1.0)
                        .onHover { hovering in
                            hoveredIndex = hovering ? index : nil
                        }
                        .help(tooltipForEntry(entry, at: index))
                }
            }
        }
    }

    private func entryForBar(at index: Int) -> SyncHistoryEntry? {
        // Display newest on right, align data to right side
        let offset = barCount - entries.count
        guard index >= offset else { return nil }
        return entries[index - offset]
    }

    private func colorForEntry(_ entry: SyncHistoryEntry?) -> Color {
        guard let entry = entry else {
            return Color.gray.opacity(0.3)
        }

        switch entry.status {
        case .success:
            return .green
        case .failure:
            return .red
        case .skipped:
            return .gray.opacity(0.5)
        }
    }

    private func tooltipForEntry(_ entry: SyncHistoryEntry?, at index: Int) -> String {
        guard let entry = entry else {
            return "No data"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: entry.timestamp)

        let statusString: String
        switch entry.status {
        case .success:
            statusString = "Success (\(entry.filesProcessed) files)"
        case .failure:
            statusString = "Failed: \(entry.errorMessage ?? "Unknown")"
        case .skipped:
            statusString = "Skipped"
        }

        return "\(timeString) - \(statusString)"
    }
}

#Preview {
    let sampleEntries = (0..<30).map { i -> SyncHistoryEntry in
        let status: SyncHistoryEntry.SyncStatus = i % 5 == 0 ? .failure : (i % 3 == 0 ? .skipped : .success)
        return SyncHistoryEntry(status: status, filesProcessed: i % 3)
    }

    return StatusGraphView(entries: sampleEntries)
        .frame(width: 300, height: 24)
        .padding()
}
