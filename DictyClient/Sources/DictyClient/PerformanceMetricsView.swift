import SwiftUI
import Charts
import AppKit

// MARK: - Models (decoded with .convertFromSnakeCase)

struct LatencyMetric: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: String
    let mode: String?
    let modelId: String?
    let modelName: String?
    let provider: String?
    let isCloud: Bool?
    let audioDurationS: Double?
    let wordCount: Int?
    let engineMs: Double?
    let endToEndMs: Double?
    let pasted: Bool?
    let incognito: Bool?
    let correctionLatencyMs: Double?
    let whisperLatencyMs: Double?
    let whisperMs: Double?
    let correctionModel: String?
    let llmLatencyMs: Double?
    let reformatModel: String?
    let formatStyle: String?

    var displayModel: String { modelName ?? modelId ?? "Unknown" }
    var latencyMs: Double { endToEndMs ?? 0 }
    var effectiveWhisperMs: Double? { whisperLatencyMs ?? whisperMs }

    /// Estimated or exact audio transcription time (Whisper STT inference)
    var transcriptionMs: Double {
        if let w = effectiveWhisperMs, w > 0 { return w }
        if let eng = engineMs, eng > 0 {
            let llm = (llmLatencyMs ?? 0) + (correctionLatencyMs ?? 0)
            return max(0, eng - llm)
        }
        let llm = (llmLatencyMs ?? 0) + (correctionLatencyMs ?? 0)
        return max(0, latencyMs - llm)
    }

    /// Formatting LLM time (if applied)
    var formattingMs: Double {
        (usedFormatting && (llmLatencyMs ?? 0) > 0) ? (llmLatencyMs ?? 0) : 0
    }

    /// Self-correction LLM time (if applied)
    var correctionMs: Double {
        (usedSelfCorrection && (correctionLatencyMs ?? 0) > 0) ? (correctionLatencyMs ?? 0) : 0
    }

    /// Total LLM processing time across formatting and self-correction
    var totalLlmMs: Double {
        formattingMs + correctionMs
    }

    /// App activation, focus return, and paste delay (or clipboard copy)
    var pasteOverheadMs: Double {
        let accounted = transcriptionMs + totalLlmMs
        return max(0, latencyMs - accounted)
    }

    /// True if self-correction was applied to this transcription.
    var usedSelfCorrection: Bool {
        (correctionLatencyMs ?? 0) > 0
    }

    /// True if an LLM formatting/styling pass was applied to this transcription.
    var usedFormatting: Bool {
        (llmLatencyMs ?? 0) > 0 || (reformatModel != nil && !reformatModel!.isEmpty)
    }

    /// Display label for formatting pass (e.g. "Qwen 2.5 1.5B · Email").
    var displayFormattingLabel: String? {
        guard usedFormatting else { return nil }
        let model = reformatModel ?? "LLM"
        if let style = formatStyle, !style.isEmpty {
            return "\(model) · \(style.capitalized)"
        }
        return model
    }

    /// Which self-correction model solved this run (nil for older records or no correction).
    var displayCorrectionModel: String? {
        guard usedSelfCorrection else { return nil }
        guard let m = correctionModel, !m.isEmpty else { return "unknown model" }
        return m
    }

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: timestamp)
    }
}

struct ModelLatencyMetric: Codable, Identifiable, Equatable {
    let modelId: String?
    let modelName: String?
    let provider: String?
    let isCloud: Bool?
    let count: Int
    let medianMs: Double
    let p90Ms: Double
    let medianXRealtime: Double?
    let fixedOverheadMs: Double?
    let msPerAudioS: Double?

    var id: String { "\(modelId ?? "?")|\(provider ?? "?")" }
    /// Same model can run as batch, live stream or pause-segmented: show which, so rows are distinguishable.
    var displayModel: String {
        var base = modelName ?? modelId ?? "Unknown"
        if let mid = modelId {
            if mid == "small.en" || (base.lowercased() == "fast" && mid.hasSuffix(".en")) {
                base = "Fast (English)"
            } else if mid == "small" || (base.lowercased() == "fast" && !mid.hasSuffix(".en")) {
                base = "Fast (Multilingual)"
            }
        }
        let p = (provider ?? "").lowercased()
        if p.contains("live") { return "\(base) · live" }
        if p.contains("segmented") { return "\(base) · segmented" }
        if isCloud == true { return "\(base) · batch" }
        return base
    }
}

struct RecentLatencyResponse: Codable { let items: [LatencyMetric] }
struct ModelLatencyResponse: Codable { let models: [ModelLatencyMetric] }
struct CorrectionModelMetric: Codable, Identifiable, Equatable {
    let correctionModel: String
    let count: Int
    let medianMs: Double
    let p90Ms: Double

    var id: String { correctionModel }
    /// Short label: drop the OpenRouter provider prefix when the name is readable on its own.
    var displayName: String {
        if let idx = correctionModel.firstIndex(of: "/") {
            return String(correctionModel[correctionModel.index(after: idx)])
        }
        return correctionModel
    }
}
struct CorrectionModelResponse: Codable { let models: [CorrectionModelMetric] }

struct FormattingModelMetric: Codable, Identifiable, Equatable {
    let reformatModel: String
    let count: Int
    let medianMs: Double
    let p90Ms: Double

    var id: String { reformatModel }
}
struct FormattingModelResponse: Codable { let models: [FormattingModelMetric] }

// MARK: - Formatting helpers

enum LatencyFormat {
    static func ms(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.2f s", v / 1000) : String(format: "%.0f ms", v)
    }
    static func duration(_ s: Double?) -> String {
        guard let s = s, s > 0 else { return "—" }
        return s >= 60 ? String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) : String(format: "%.1f s", s)
    }
    static func modeLabel(_ mode: String?) -> String {
        switch mode {
        case "dictation": return "Dictation"
        case "meeting", "focused_meeting": return "Meeting"
        case "file_transcription": return "File"
        case "librarian": return "Librarian"
        case let m?: return m.capitalized
        default: return "—"
        }
    }
    /// Accent for self-correction markers: uses the single user-selected appAccent
    static var correctionAccent: Color { .appAccent }

    /// Palette for model bars & legends: primary model uses appAccent, others neutral greys
    static var pastelPalette: [Color] {
        [
            Color.appAccent,
            Color.primary.opacity(0.45),
            Color.primary.opacity(0.35),
            Color.primary.opacity(0.25),
            Color.primary.opacity(0.55),
            Color.primary.opacity(0.65),
            Color.primary.opacity(0.20),
            Color.primary.opacity(0.75)
        ]
    }
}

// MARK: - Time Saved Formatter
public enum TimeSavedFormatter {
    public static func format(words: Int, speakingWpm: Int) -> String {
        guard words > 0 else { return "—" }
        let typingTimeMins = Double(words) / 40.0
        let userSpeakingWpm = speakingWpm > 0 ? Double(speakingWpm) : 150.0
        let speakingTimeMins = Double(words) / userSpeakingWpm
        let savedMins = max(0, typingTimeMins - speakingTimeMins)
        if savedMins <= 0 {
            return "—"
        } else if savedMins < 1.0 {
            return "<1 min"
        } else if savedMins >= 60.0 {
            return String(format: "%.1fh", savedMins / 60)
        } else {
            return "\(Int(savedMins))m"
        }
    }
}


// MARK: - Help Popover Component

private struct MetricsHelpButton: View {
    @State private var showPopover = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(showPopover ? .white : .sageGreen)
                .padding(3)
                .background(showPopover ? Color.sageGreen : Color.primary.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Metrics Guide: what each metric means")
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(.sageGreen)
                        .font(.system(size: 13, weight: .bold))
                    Text("Understanding Latency Metrics")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    metricRow(
                        title: "Latency (Stop → Paste)",
                        desc: "The total time from the instant you stop recording until the final text is pasted at your cursor."
                    )
                    metricRow(
                        title: "Median (Typical Speed)",
                        desc: "The middle response time. Half of your dictations are faster, half are slower. Best indicator of daily experience."
                    )
                    metricRow(
                        title: "p90 (Worst 10%)",
                        desc: "90% of transcriptions finish faster than this. Shows your worst-case lag (e.g. cold starts or long clips)."
                    )
                    metricRow(
                        title: "Fixed Overhead",
                        desc: "Base setup time per dictation (mic cleanup, app switching, paste), regardless of how long you spoke."
                    )
                    metricRow(
                        title: "Per Audio Second",
                        desc: "How much extra processing time is needed for each second of spoken audio. Smaller number = faster speech model."
                    )
                    metricRow(
                        title: "Local vs. Cloud",
                        desc: "Local models run on your Mac's Apple Silicon Neural Engine (offline). Cloud models stream to remote AI servers."
                    )
                }

                Text("Tip: Hover over any bar in the chart to inspect details for that transcription.")
                    .font(.system(size: 10))
                    .foregroundColor(.dictySecondary)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
    }

    private func metricRow(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.dictySecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Card

/// "Advanced" card: stop -> paste latency of the last 10 transcriptions + per-model summary.
struct LatencyMetricsCard: View {
    @EnvironmentObject var engineClient: EngineClient
    @State private var hoveredId: String?
    @State private var copied = false
    /// How many of the most recent runs the chart shows (or "all" → distribution histogram).
    @AppStorage("latencyChartRange") private var chartRange: String = "10"

    private var rangeLimit: Int {
        let n = Int(chartRange) ?? 10
        return max(10, min(n, 500))
    }

    // MARK: Distribution histogram ("All" mode)

    /// Log-ish latency buckets in ms: short dictation runs cluster below 1s, spikes stretch to seconds.
    private static let histogramEdges: [Double] = [250, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000]

    struct HistogramBucket: Identifiable {
        let id: String
        let axisLabel: String
        let fullLabel: String
        let count: Int
    }

    private var histogramItems: [HistogramBucket] {
        let lat = items.map(\.latencyMs)
        var counts: [Int] = Array(repeating: 0, count: Self.histogramEdges.count + 1)
        for ms in lat {
            var idx = Self.histogramEdges.count
            for (i, edge) in Self.histogramEdges.enumerated() where ms < edge {
                idx = i
                break
            }
            counts[idx] += 1
        }
        let sec: [String] = ["0.25", "0.5", "0.75", "1", "1.5", "2", "3", "5", "10"]
        var label = "0–\(sec[0])"
        var axis = "0–\(sec[0])"
        var out: [HistogramBucket] = []
        for i in 0..<counts.count {
            if i > 0 {
                let lower = sec[i - 1]
                if i == counts.count - 1 {
                    label = ">\(lower) s"
                    axis = "\(lower)s+"
                } else {
                    label = "\(lower)–\(sec[i])"
                    axis = sec[i].hasSuffix("0") ? "\(sec[i])s" : sec[i]
                }
            } else {
                label = "0–\(sec[0])"
                axis = "0–\(sec[0])"
            }
            out.append(HistogramBucket(id: label + "-\(i)", axisLabel: axis, fullLabel: "\(label) s", count: counts[i]))
        }
        return out
    }

    private var histogramChart: some View {
        Chart {
            ForEach(histogramItems.filter { $0.count > 0 }) { bucket in
                BarMark(
                    x: .value("Latency", bucket.fullLabel),
                    y: .value("Runs", bucket.count)
                )
                .foregroundStyle(LatencyFormat.pastelPalette[0])
                .opacity(0.85)
                .cornerRadius(3)
                .annotation(position: .top, spacing: 1) {
                    if bucket.count >= 2 {
                        Text("\(bucket.count)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.dictySecondary)
                    }
                }
            }
        }
        .chartForegroundStyleScale(range: LatencyFormat.pastelPalette)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .font(.system(size: 8))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel()
                    .font(.system(size: 9))
            }
        }
        .help("Distribution of \(items.count) recorded runs by stop → paste latency. Fastest buckets on the left.")
    }

    private var histogramSummary: some View {
        let sorted = items.map(\.latencyMs).sorted()
        let median = sorted.isEmpty ? 0 : (sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2)
        let p90idx = max(0, min(sorted.count - 1, Int((Double(sorted.count) * 0.9).rounded(.up) - 1)))
        let p90 = sorted.isEmpty ? 0 : sorted[p90idx]
        return Text("Distribution of \(items.count) runs · median \(LatencyFormat.ms(median)) · p90 \(LatencyFormat.ms(p90)). Highest bars show where your latency usually lands.")
            .font(.system(size: 10))
            .foregroundColor(.dictySecondary)
    }

    private var chartTitle: String {
        chartRange == "all"
            ? "Latency distribution: all recorded runs"
            : "Latency: last \(items.count) transcriptions"
    }

    private var items: [LatencyMetric] {
        // Engine returns newest first; chart reads left (oldest) -> right (newest)
        Array(engineClient.recentLatencyMetrics.reversed())
    }

    /// Derived chart values, computed once per render (not once per bar).
    private struct ChartStats {
        let median: Double
        /// Bars above 3x median are visually clipped so a long meeting doesn't flatten the chart.
        let cap: Double
    }

    private static func stats(for items: [LatencyMetric]) -> ChartStats {
        let v = items.map(\.latencyMs).sorted()
        guard !v.isEmpty else { return ChartStats(median: 0, cap: .infinity) }
        let median = v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
        guard median > 0 else { return ChartStats(median: 0, cap: .infinity) }
        let cap = max(median * 3, v.last(where: { $0 <= median * 3 }) ?? median)
        return ChartStats(median: median, cap: cap)
    }

    /// Above this many bars, per-bar annotations (↑ / pencil) are dropped: unreadable and costly.
    private static let denseThreshold = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Text(chartTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    MetricsHelpButton()
                }
                Spacer()
                Button(action: copyMarkdown) {
                    Label("Copy as Markdown", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .medium))
                        .opacity(copied ? 0 : 1)
                        .overlay {
                            if copied {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)).foregroundColor(.appAccent)
                            }
                        }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy latency stats as Markdown")
                .disabled(items.isEmpty)
            }
            HStack(spacing: 10) {
                Text("Time from stopping the recording until the text is pasted.")
                    .font(.system(size: 11))
                    .foregroundColor(.dictySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Picker("Range", selection: $chartRange) {
                    Text("10").tag("10")
                    Text("50").tag("50")
                    Text("100").tag("100")
                    Text("All").tag("all")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 168)
                .controlSize(.small)
                .help("How many of the most recent transcriptions the chart shows. \"All\" shows a distribution histogram instead.")
            }

            if items.isEmpty {
                Text("No measured transcriptions yet. Dictate something to see latency.")
                    .font(.system(size: 12))
                    .foregroundColor(.dictySecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                    .frame(height: 170)
                if chartRange == "all" {
                    histogramSummary
                } else {
                    hoverDetail
                        .frame(minHeight: 16, alignment: .top)
                }
            }

            LatencyTablesView(
                modelLatencyMetrics: engineClient.modelLatencyMetrics,
                formattingModelMetrics: engineClient.formattingModelMetrics,
                correctionModelMetrics: engineClient.correctionModelMetrics,
                hardwareSummary: engineClient.hardwareSummary
            )
            .equatable()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { engineClient.fetchPerformanceMetrics(recentLimit: rangeLimit) }
        .onChange(of: engineClient.statsPeriod) { _, _ in engineClient.fetchPerformanceMetrics(recentLimit: rangeLimit) }
        .onChange(of: chartRange) { _, _ in engineClient.fetchPerformanceMetrics(recentLimit: rangeLimit) }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            engineClient.fetchPerformanceMetrics(recentLimit: rangeLimit)
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        if chartRange == "all" {
            histogramChart
        } else {
            barChart
        }
    }

    private struct BarItemStage: Identifiable {
        var id: String { stage }
        let stage: String
        let ms: Double
    }

    private struct PreparedBar: Identifiable {
        let id: String
        let index: Int
        let item: LatencyMetric
        let stages: [BarItemStage]
        let isClipped: Bool
    }

    private static func prepareBars(bars: [LatencyMetric], cap: Double) -> [PreparedBar] {
        bars.enumerated().map { index, item in
            let total = item.latencyMs
            let isClipped = cap > 0 && total > cap
            let scale = isClipped ? (cap / total) : 1.0

            let t = item.transcriptionMs
            let f = item.formattingMs
            let c = item.correctionMs
            let p = item.pasteOverheadMs

            var stages: [BarItemStage] = []
            if t > 0 {
                stages.append(BarItemStage(stage: "Transcription", ms: t * scale))
            }
            if f > 0 {
                stages.append(BarItemStage(stage: "Formatting", ms: f * scale))
            }
            if c > 0 {
                stages.append(BarItemStage(stage: "Correction", ms: c * scale))
            }
            if p > 0 {
                stages.append(BarItemStage(stage: "Focus & paste", ms: p * scale))
            }
            if stages.isEmpty && total > 0 {
                stages.append(BarItemStage(stage: "Transcription", ms: min(total, cap)))
            }
            return PreparedBar(id: item.id, index: index + 1, item: item, stages: stages, isClipped: isClipped)
        }
    }

    private var barChart: some View {
        // Snapshot once: `items` copies + reverses the array on every access.
        let bars = items
        let s = Self.stats(for: bars)
        let dense = bars.count > Self.denseThreshold
        let prepared = Self.prepareBars(bars: bars, cap: s.cap)
        return Chart {
            ForEach(prepared) { bar in
                ForEach(Array(bar.stages.enumerated()), id: \.element.id) { segIndex, seg in
                    let hasAnnotation = !dense && segIndex == bar.stages.count - 1 && (bar.isClipped || bar.item.usedFormatting || bar.item.usedSelfCorrection)
                    if hasAnnotation {
                        BarMark(
                            x: .value("Transcription", "\(bar.index)"),
                            y: .value("Stop → paste (ms)", seg.ms)
                        )
                        .foregroundStyle(by: .value("Stage", seg.stage))
                        .opacity(hoveredId == nil || hoveredId == bar.id ? 1 : 0.45)
                        .cornerRadius(dense ? 1 : (segIndex == bar.stages.count - 1 ? 4 : 0))
                        .annotation(position: .top, spacing: 2) {
                            HStack(spacing: 2) {
                                if bar.isClipped {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.dictySecondary)
                                }
                                if bar.item.usedFormatting {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(Color.appAccent)
                                }
                                if bar.item.usedSelfCorrection {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(LatencyFormat.correctionAccent)
                                }
                            }
                        }
                    } else {
                        BarMark(
                            x: .value("Transcription", "\(bar.index)"),
                            y: .value("Stop → paste (ms)", seg.ms)
                        )
                        .foregroundStyle(by: .value("Stage", seg.stage))
                        .opacity(hoveredId == nil || hoveredId == bar.id ? 1 : 0.45)
                        .cornerRadius(dense ? 1 : (segIndex == bar.stages.count - 1 ? 4 : 0))
                    }
                }
            }
            if s.median > 0 {
                RuleMark(y: .value("Median", s.median))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.appAccent.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("median \(LatencyFormat.ms(s.median))")
                            .font(.system(size: 9))
                            .foregroundColor(.dictySecondary)
                    }
            }
        }
        .chartForegroundStyleScale([
            "Transcription": Color.primary.opacity(0.48),
            "Formatting": Color.appAccent,
            "Correction": LatencyFormat.correctionAccent.opacity(0.75),
            "Focus & paste": Color.primary.opacity(0.20)
        ])
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(LatencyFormat.ms(v)).font(.system(size: 9)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        var newId: String?
                        if case .active(let location) = phase,
                           let plotFrame = proxy.plotFrame {
                            let origin = geo[plotFrame].origin
                            if let label: String = proxy.value(atX: location.x - origin.x),
                               let idx = Int(label), idx >= 1, idx <= bars.count {
                                newId = bars[idx - 1].id
                            }
                        }
                        // Only invalidate the view when the hovered bar actually changes,
                        // not on every mouse-move / scroll frame.
                        if newId != hoveredId { hoveredId = newId }
                    }
            }
        }
    }

    @ViewBuilder
    private var hoverDetail: some View {
        if let id = hoveredId, let item = items.first(where: { $0.id == id }) {
            let stats = Self.stats(for: items)
            // Semantic warning color rule:
            // Display latency in amber only if it is an outlier exceeding 2× the median.
            // All other latency values stay neutral .primary to avoid decorative colors.
            let isOutlier = stats.median > 0 && item.latencyMs > (2.0 * stats.median)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(LatencyFormat.ms(item.latencyMs))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(isOutlier ? Color.warmAmber : .primary)
                    Text(item.displayModel).font(.system(size: 11, weight: .semibold))
                    Text(item.provider ?? "").font(.system(size: 10)).foregroundColor(.dictySecondary).lineLimit(1)
                    Text(LatencyFormat.modeLabel(item.mode)).font(.system(size: 10)).foregroundColor(.dictySecondary)
                    Text("audio \(LatencyFormat.duration(item.audioDurationS))").font(.system(size: 10)).foregroundColor(.dictySecondary)
                    Text("\(item.wordCount ?? 0) words").font(.system(size: 10)).foregroundColor(.dictySecondary)
                    if item.pasted == false {
                        Text("copied").font(.system(size: 10)).foregroundColor(.dictySecondary)
                    }
                    if item.incognito == true {
                        Label("Incognito", systemImage: "eye.slash").font(.system(size: 10)).foregroundColor(.dictySecondary)
                    }
                    Spacer(minLength: 0)
                }
                // Detailed Stage Breakdown (accounting for 100% of end-to-end latency)
                HStack(spacing: 12) {
                    // Stage 1: Audio speech-to-text
                    let whisper = item.transcriptionMs
                    if whisper > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 8))
                                .foregroundColor(.dictySecondary)
                            Text("Transcription \(LatencyFormat.ms(whisper))")
                                .font(.system(size: 10))
                                .foregroundColor(.dictySecondary)
                        }
                    }

                    // Stage 2: Formatting / Styling LLM pass
                    if item.usedFormatting, let llmMs = item.llmLatencyMs, llmMs > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 8))
                                .foregroundColor(Color.appAccent)
                            Text("Formatting \(LatencyFormat.ms(llmMs))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.appAccent)
                            if let fl = item.displayFormattingLabel {
                                Text("(\(fl))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.dictySecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Stage 3: Self-correction LLM pass
                    if item.usedSelfCorrection, let corrMs = item.correctionLatencyMs, corrMs > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
                                .foregroundColor(LatencyFormat.correctionAccent)
                            Text("Correction \(LatencyFormat.ms(corrMs))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(LatencyFormat.correctionAccent)
                            if let cm = item.displayCorrectionModel {
                                Text("(\(cm))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.dictySecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Explicit indication when no LLM processing took place
                    if !item.usedFormatting && !item.usedSelfCorrection {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles.slash")
                                .font(.system(size: 8))
                                .foregroundColor(.dictySecondary)
                            Text("No LLM")
                                .font(.system(size: 10))
                                .foregroundColor(.dictySecondary)
                        }
                        .help("Transcribed directly with Whisper; no formatting or self-correction LLM was called.")
                    }

                    // Stage 4: App focus return and Cmd+V paste (or clipboard copy)
                    let pasteMs = item.pasteOverheadMs
                    if pasteMs > 15 {
                        HStack(spacing: 4) {
                            Image(systemName: item.pasted == true ? "keyboard" : "doc.on.clipboard")
                                .font(.system(size: 8))
                                .foregroundColor(.dictySecondary)
                            Text(item.pasted == true ? "Focus & paste \(LatencyFormat.ms(pasteMs))" : "Clipboard copy \(LatencyFormat.ms(pasteMs))")
                                .font(.system(size: 10))
                                .foregroundColor(.dictySecondary)
                        }
                        .help(item.pasted == true ? "Time for macOS to activate the target window, wait for focus, and paste text via Cmd+V" : "Time to copy the result to the macOS clipboard")
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        } else {
            Text("Hover a bar for details. Bars marked ↑ are clipped to keep the chart readable.")
                .font(.system(size: 10))
                .foregroundColor(.dictySecondary)
        }
    }

    // MARK: Markdown export

    // MARK: Markdown export

    private func copyMarkdown() {
        var md = "### Dicty latency report\n\n"
        if !engineClient.hardwareSummary.isEmpty { md += "**Hardware:** \(engineClient.hardwareSummary)\n\n" }
        md += "#### Last \(engineClient.recentLatencyMetrics.count) transcriptions\n\n"
        md += "| Time | Model | Provider | Mode | Audio | Words | Stop → paste |\n|---|---|---|---|---|---|---|\n"
        let tf = DateFormatter(); tf.dateFormat = "MMM d HH:mm"
        for i in engineClient.recentLatencyMetrics {
            let time = i.date.map { tf.string(from: $0) } ?? i.timestamp
            let corrStr: String
            if let cm = i.displayCorrectionModel, let cLat = i.correctionLatencyMs {
                corrStr = " +\(Int(cLat))ms correction (\(cm))"
            } else if let cLat = i.correctionLatencyMs {
                corrStr = " +\(Int(cLat))ms correction"
            } else {
                corrStr = ""
            }
            let fmtStr: String
            if let fl = i.displayFormattingLabel, let fLat = i.llmLatencyMs, fLat > 0 {
                fmtStr = " +\(Int(fLat))ms styling (\(fl))"
            } else {
                fmtStr = ""
            }
            md += "| \(time) | \(i.displayModel) | \(i.provider ?? "—") | \(LatencyFormat.modeLabel(i.mode)) | \(LatencyFormat.duration(i.audioDurationS)) | \(i.wordCount ?? 0) | \(LatencyFormat.ms(i.latencyMs))\(fmtStr)\(corrStr)\(i.pasted == false ? " (copied)" : "") |\n"
        }
        if !engineClient.modelLatencyMetrics.isEmpty {
            md += "\n#### By model\n\n| Model | Where | Runs | Median | p90 | Fixed overhead | Per audio second |\n|---|---|---|---|---|---|---|\n"
            for m in engineClient.modelLatencyMetrics {
                let overhead = m.fixedOverheadMs.map { LatencyFormat.ms($0) } ?? "—"
                let perSec = m.msPerAudioS.map { String(format: "+%.1f ms/s", $0) } ?? "—"
                md += "| \(m.displayModel) | \(m.isCloud == true ? "Cloud" : "Local") | \(m.count) | \(LatencyFormat.ms(m.medianMs)) | \(LatencyFormat.ms(m.p90Ms)) | \(overhead) | \(perSec) |\n"
            }
            md += "\n_Latency ≈ fixed overhead + per-audio-second × clip length (least-squares fit; shown with 3+ runs spanning 5+ s)._\n"
        }
        if !engineClient.formattingModelMetrics.isEmpty {
            md += "\n#### Formatting & styling by model\n\n| Styling LLM | Runs | Median | p90 |\n|---|---|---|---|\n"
            for m in engineClient.formattingModelMetrics {
                md += "| \(m.reformatModel) | \(m.count) | \(LatencyFormat.ms(m.medianMs)) | \(LatencyFormat.ms(m.p90Ms)) |\n"
            }
        }
        if !engineClient.correctionModelMetrics.isEmpty {
            md += "\n#### Self-correction by model\n\n| Correction LLM | Runs | Median | p90 |\n|---|---|---|---|\n"
            for m in engineClient.correctionModelMetrics {
                md += "| \(m.correctionModel) | \(m.count) | \(LatencyFormat.ms(m.medianMs)) | \(LatencyFormat.ms(m.p90Ms)) |\n"
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Latency Comparison Tables (Isolated for Equatable performance)

struct LatencyTablesView: View, Equatable {
    let modelLatencyMetrics: [ModelLatencyMetric]
    let formattingModelMetrics: [FormattingModelMetric]
    let correctionModelMetrics: [CorrectionModelMetric]
    let hardwareSummary: String

    nonisolated static func == (lhs: LatencyTablesView, rhs: LatencyTablesView) -> Bool {
        lhs.modelLatencyMetrics == rhs.modelLatencyMetrics &&
        lhs.formattingModelMetrics == rhs.formattingModelMetrics &&
        lhs.correctionModelMetrics == rhs.correctionModelMetrics &&
        lhs.hardwareSummary == rhs.hardwareSummary
    }

    private var allLocal: Bool {
        modelLatencyMetrics.allSatisfy { $0.isCloud != true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !modelLatencyMetrics.isEmpty {
                Divider()
                modelTable
            }

            if !formattingModelMetrics.isEmpty {
                Divider()
                formattingTable
            }

            if !correctionModelMetrics.isEmpty {
                Divider()
                correctionTable
            }

            if !hardwareSummary.isEmpty {
                Text(hardwareSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.dictySecondary)
            }
        }
    }

    private var modelTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By model on this Mac")
                .font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    header("Model")
                    if !allLocal {
                        header("Where")
                    }
                    header("Runs")
                    header("Median"); header("p90")
                    header("Fixed overhead").help("Time every transcription costs regardless of length: stopping the mic, HTTP, focus return, paste.")
                    header("Per audio second").help("Extra time per second of speech: the model's actual speed. Needs 3+ runs with clips differing by 5s+.")
                }
                ForEach(modelLatencyMetrics) { m in
                    GridRow {
                        HStack(spacing: 6) {
                            Text(m.displayModel).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            if allLocal && m.isCloud == true {
                                Text("Cloud")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.08))
                                    .foregroundColor(.primary)
                                    .cornerRadius(3)
                            }
                        }
                        if !allLocal {
                            Text(m.isCloud == true ? "Cloud" : "Local")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(m.isCloud == true ? Color.primary.opacity(0.08) : Color.appAccent.opacity(0.18))
                                .foregroundColor(m.isCloud == true ? .primary : .appAccent)
                                .cornerRadius(4)
                        }
                        Text("\(m.count)").font(.system(size: 11, design: .monospaced))
                        Text(LatencyFormat.ms(m.medianMs))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(LatencyFormat.ms(m.p90Ms)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                        Text(m.fixedOverheadMs.map { LatencyFormat.ms($0) } ?? "—")
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                        Text(m.msPerAudioS.map { String(format: "+%.1f ms/s", $0) } ?? "—")
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            .help(m.msPerAudioS == nil ? "Needs 3+ runs with clip lengths differing by at least 5 s." : "")
                    }
                }
            }
        }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundColor(.dictySecondary)
    }

    private var formattingTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Formatting & styling by model")
                .font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    header("Styling LLM"); header("Runs")
                    header("Median").help("Median time the formatting pass adds. Lower is faster.")
                    header("p90")
                }
                ForEach(formattingModelMetrics) { m in
                    GridRow {
                        Text(m.reformatModel).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                        Text("\(m.count)").font(.system(size: 11, design: .monospaced))
                        Text(LatencyFormat.ms(m.medianMs))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(LatencyFormat.ms(m.p90Ms)).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }

    private var correctionTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Self-correction by model")
                .font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    header("Correction LLM"); header("Runs")
                    header("Median").help("Median time the correction pass adds before the text is usable. Lower is faster.")
                    header("p90")
                }
                ForEach(correctionModelMetrics) { m in
                    GridRow {
                        Text(m.correctionModel).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                            .help(m.displayName)
                        Text("\(m.count)").font(.system(size: 11, design: .monospaced))
                        Text(LatencyFormat.ms(m.medianMs))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(LatencyFormat.ms(m.p90Ms)).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }
}

// MARK: - Insights View (Full Performance & Latency Analytics)

struct InsightsView: View {
    @EnvironmentObject var engineClient: EngineClient
    
    var activeModelName: String {
        if let model = engineClient.models.first(where: { $0.id == engineClient.activeModel }) {
            return model.name
        }
        return engineClient.activeModel.isEmpty ? "None" : engineClient.activeModel.uppercased()
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Header with Period Picker (single period picker)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insights")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Detailed dictation speed, time saved, and model latency metrics.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.dictySecondary)
                    }
                    Spacer()
                    
                    Picker("Period", selection: $engineClient.statsPeriod) {
                        Text("Today").tag("day")
                        Text("This Week").tag("week")
                        Text("This Month").tag("month")
                        Text("All Time").tag("all")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 120)
                    .onChange(of: engineClient.statsPeriod) { _, _ in
                        engineClient.fetchStats()
                    }
                }
                
                // 6-metric grid
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 16) {
                        MetricItem(title: "Words spoken", value: "\(engineClient.totalWordsSpoken)", icon: "text.word.spacing")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().frame(height: 30)
                        
                        MetricItem(title: "Speaking speed", value: "\(engineClient.avgSpeakingWpm) WPM", icon: "waveform")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().frame(height: 30)
                        
                        MetricItem(title: "Engine speed", value: "\(engineClient.avgEngineWpm) WPM", icon: "bolt.fill", valueColor: .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help("Transcription generation speed in words per minute.")
                    }
                    
                    Divider()
                    
                    HStack(alignment: .center, spacing: 16) {
                        MetricItem(title: "Active model", value: activeModelName, icon: "cpu", valueColor: .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().frame(height: 30)
                        
                        let timeString = TimeSavedFormatter.format(words: engineClient.totalWordsSpoken, speakingWpm: engineClient.avgSpeakingWpm)
                        MetricItem(title: "Time saved", value: timeString, icon: "clock.badge.checkmark.fill", valueColor: .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().frame(height: 30)
                        
                        MetricItem(title: "Librarian edits", value: "\(engineClient.librarianUpdates)", icon: "books.vertical.fill", valueColor: .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Full LatencyMetricsCard
                LatencyMetricsCard()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            engineClient.fetchStats()
            engineClient.fetchPerformanceMetrics()
        }
    }
}

