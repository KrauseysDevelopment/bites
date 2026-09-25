// WeightView.swift
import SwiftUI
import Charts

struct WeightView: View {
    @EnvironmentObject private var store: DiaryStore

    @State private var range: WeightRange = .month
    @State private var showingEntry = false
    @State private var weightInput = ""
    @State private var entryDate = Date()
    @State private var selectedDate: Date?

    // MARK: - Data

    /// Ascending, one point per day.
    private var allPoints: [WeightPoint] {
        let sorted = store.weightEntries.sorted { $0.date < $1.date }
        // Trailing 7-day mean smooths daily water-weight noise, which is the
        // whole reason a scale chart is hard to read raw.
        return sorted.enumerated().map { index, entry in
            let window = sorted[max(0, index - 6)...index]
            let mean = window.map(\.pounds).reduce(0, +) / Double(window.count)
            return WeightPoint(date: entry.date, pounds: entry.pounds, average: mean)
        }
    }

    private var points: [WeightPoint] {
        guard let cutoff = range.cutoff else { return allPoints }
        return allPoints.filter { $0.date >= cutoff }
    }

    private var domain: ClosedRange<Double> {
        let values = points.flatMap { [$0.pounds, $0.average] }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        // Never zero-based: on a scale chart the change is the story, and a
        // zero baseline flattens every real movement into a straight line.
        let pad = max((hi - lo) * 0.18, 1.5)
        return (lo - pad)...(hi + pad)
    }

    private var first: WeightPoint? { points.first }
    private var latest: WeightPoint? { points.last }

    private var change: Double? {
        guard let first, let latest, points.count > 1 else { return nil }
        return latest.pounds - first.pounds
    }

    private var selectedPoint: WeightPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // One filter row above everything it scopes.
                Picker("Range", selection: $range) {
                    ForEach(WeightRange.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if points.count < 2 {
                    emptyState
                } else {
                    chartCard
                    statsRow
                }

                historySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    weightInput = store.latestWeight > 0 ? String(format: "%.1f", store.latestWeight) : ""
                    entryDate = Date()
                    showingEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Log weight")
            }
        }
        .sheet(isPresented: $showingEntry) { entrySheet }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The readout doubles as the direct label, so no number sits on
            // every point and the value is never tooltip-only.
            HStack(alignment: .firstTextBaseline) {
                if let point = selectedPoint {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(point.pounds, specifier: "%.1f") lb")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(point.date, format: .dateTime.weekday().month().day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let latest {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(latest.pounds, specifier: "%.1f") lb")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Latest · \(range.label) view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                legend
            }

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Floor", domain.lowerBound),
                        yEnd: .value("Average", point.average)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Average", point.average)
                    )
                    .foregroundStyle(Color.indigo)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Raw readings stay visible but recede, so the trend leads.
                if showsDailyPoints {
                    ForEach(points) { point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.pounds)
                        )
                        .foregroundStyle(Color.indigo.opacity(0.35))
                        .symbolSize(28)
                    }
                }

                if let point = selectedPoint {
                    RuleMark(x: .value("Selected", point.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(
                        x: .value("Selected", point.date),
                        y: .value("Weight", point.pounds)
                    )
                    .foregroundStyle(Color.indigo)
                    .symbolSize(90)
                }
            }
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.14))
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text("\(raw, specifier: "%.0f")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range.tickCount)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.10))
                    AxisValueLabel(format: range.axisFormat)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $selectedDate)
            // Height covers the plot plus the x-axis band, so the labels are
            // never clipped into a tiny nested scroll.
            .frame(height: 210)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    private var showsDailyPoints: Bool { points.count <= 60 }

    private var legend: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 5) {
                Capsule().fill(Color.indigo).frame(width: 14, height: 2)
                Text("7-day avg")
            }
            if showsDailyPoints {
                HStack(spacing: 5) {
                    Circle().fill(Color.indigo.opacity(0.35)).frame(width: 6, height: 6)
                    Text("Daily")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("Start", value: first.map { String(format: "%.1f", $0.pounds) } ?? "—", tint: .secondary)
            statTile("Current", value: latest.map { String(format: "%.1f", $0.pounds) } ?? "—", tint: .indigo)
            statTile(
                "Change",
                value: change.map { String(format: "%+.1f", $0) } ?? "—",
                tint: (change ?? 0) <= 0 ? .green : .orange
            )
        }
    }

    private func statTile(_ label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - History (the readable twin of the chart)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text("\(points.count) entries")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if points.isEmpty {
                Text("Nothing logged in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.date, format: .dateTime.weekday(.abbreviated).month().day())
                            .font(.subheadline)
                        Spacer()
                        if let delta = deltaFromPrevious(point) {
                            Text(String(format: "%+.1f", delta))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(delta <= 0 ? .green : .orange)
                        }
                        Text("\(point.pounds, specifier: "%.1f") lb")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 78, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .contextMenu {
                        Button(role: .destructive) {
                            store.deleteWeight(on: point.date)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func deltaFromPrevious(_ point: WeightPoint) -> Double? {
        guard let index = points.firstIndex(where: { $0.id == point.id }), index > 0 else { return nil }
        return point.pounds - points[index - 1].pounds
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 28))
                    .foregroundStyle(.indigo.opacity(0.6))
            }
            Text(store.weightEntries.isEmpty ? "No weigh-ins yet" : "Not enough data in this range")
                .font(.subheadline.bold())
            Text("Two entries are enough to draw a trend.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Entry

    private var entrySheet: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("e.g. 185.5", text: $weightInput)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("lb").foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEntry = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let weight = Double(weightInput), weight > 0 {
                            store.logWeight(weight, on: entryDate)
                        }
                        weightInput = ""
                        showingEntry = false
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(weightInput) == nil)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}

// MARK: - Supporting types

struct WeightPoint: Identifiable, Hashable {
    let date: Date
    let pounds: Double
    let average: Double
    var id: Date { date }
}

enum WeightRange: String, CaseIterable, Identifiable {
    case week, month, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:  return "7D"
        case .month: return "1M"
        case .year:  return "1Y"
        case .all:   return "All"
        }
    }

    var days: Int? {
        switch self {
        case .week:  return 7
        case .month: return 30
        case .year:  return 365
        case .all:   return nil
        }
    }

    var cutoff: Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))
    }

    var tickCount: Int {
        switch self {
        case .week:  return 7
        case .month: return 5
        case .year:  return 6
        case .all:   return 5
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .week:  return .dateTime.weekday(.narrow)
        case .month: return .dateTime.month(.abbreviated).day()
        case .year:  return .dateTime.month(.narrow)
        case .all:   return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }
}

#Preview {
    NavigationStack {
        WeightView()
            .environmentObject(DiaryStore.shared)
    }
}
