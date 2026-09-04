//
//  Charts.swift
//  CabFit
//
//  The chart layer behind the Reports tab: a validated palette, shared mark specs
//  and four chart forms. Everything is drawn with plain SwiftUI shapes so it runs
//  on iOS 14 (Swift Charts is iOS 16+).
//
//  Colours here are NOT hand-picked. The categorical slots and the ordinal ramp were
//  checked against the lightness band, chroma floor, protan/deutan separation, the
//  normal-vision floor and contrast-vs-surface, in both light and dark, on this app's
//  own card colours. Re-validate before changing any hex below.
//

import SwiftUI

// MARK: - Chart palette

enum CFChart {

    // Categorical — identity only, fixed order, never cycled.
    // Deliberately excludes green/amber/red: those are reserved for status, and a
    // series wearing a status colour makes "is this bad?" unanswerable.
    static let cat: [Color] = [
        .dyn("1F6FE0", "4A82F5"),   // 1 blue
        .dyn("F77A1E", "DB7524"),   // 2 orange
        .dyn("6F4BD8", "8F72E5"),   // 3 violet
        .dyn("0E9AA7", "1FA2AE")    // 4 teal
    ]

    /// Ordinal ramp — one hue, monotone lightness, for ordered buckets (module widths).
    /// Light mode reads light→dark; dark mode flips the anchor.
    static let ordinal: [Color] = [
        .dyn("8FB6E8", "3A5D9B"),
        .dyn("72A0E0", "4A75B8"),
        .dyn("5187D6", "5B8ED4"),
        .dyn("3569BE", "77A8E4"),
        .dyn("23509A", "96C0EF"),
        .dyn("153668", "BBD8F8")
    ]

    /// The colour a mark takes when it is context rather than the point.
    static let deemphasis = Color.dyn("C6D5E8", "36486B")
    /// Unfilled track behind a meter — a lighter step of the same ramp.
    static let track = Color.dyn("E4EDF8", "22314F")
    /// Hairline grid, one step off the surface.
    static let grid = Color.dyn("E8EFF8", "24334F")

    static func categorical(_ i: Int) -> Color { cat[i % cat.count] }

    /// Ordinal step for position `i` of `n`, spread across the whole ramp so a
    /// three-bucket chart still reads as an ordered progression.
    static func ordinalStep(_ i: Int, of n: Int) -> Color {
        guard n > 1 else { return ordinal[ordinal.count / 2] }
        let t = Double(i) / Double(n - 1)
        let idx = Int((t * Double(ordinal.count - 1)).rounded())
        return ordinal[min(ordinal.count - 1, max(0, idx))]
    }
}

// MARK: - Mark specs

private enum Mark {
    static let barThickness: CGFloat = 22      // cap; never fill the whole band
    static let radius: CGFloat = 4             // rounded data-end
    static let gap: CGFloat = 2                // surface gap between touching fills
    static let hairline: CGFloat = 1
}

/// Rounds only the corners at a mark's data-end. A bar is square where it meets its
/// baseline and rounded where the value stops; a stacked bar rounds only its outer
/// ends, so the segments read as one bar separated by gaps rather than as pills.
struct DataEnd: Shape {
    var topLeading: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomTrailing: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let tl = min(topLeading, limit), bl = min(bottomLeading, limit)
        let tt = min(topTrailing, limit), bt = min(bottomTrailing, limit)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tt, y: rect.minY))
        if tt > 0 {
            p.addArc(center: CGPoint(x: rect.maxX - tt, y: rect.minY + tt), radius: tt,
                     startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bt))
        if bt > 0 {
            p.addArc(center: CGPoint(x: rect.maxX - bt, y: rect.maxY - bt), radius: bt,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        p.closeSubpath()
        return p
    }

    /// Grows left-to-right: square at the baseline, rounded at the value.
    static func bar(_ r: CGFloat) -> DataEnd { DataEnd(topTrailing: r, bottomTrailing: r) }
    /// Grows upward: square on the axis, rounded at the cap.
    static func column(_ r: CGFloat) -> DataEnd { DataEnd(topLeading: r, topTrailing: r) }
    /// One slice of a horizontal stack — only the outer ends of the whole bar round.
    static func slice(_ r: CGFloat, first: Bool, last: Bool) -> DataEnd {
        DataEnd(topLeading: first ? r : 0, bottomLeading: first ? r : 0,
                topTrailing: last ? r : 0, bottomTrailing: last ? r : 0)
    }
}

/// One slice of a part-to-whole bar, or one bar in a set.
struct ChartDatum: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    /// Pre-formatted for display — charts never guess at units or currency.
    let display: String
    var color: Color
    var isEmphasised: Bool = true
    /// Optional status note. When present it is shown as icon + text, never colour alone.
    var status: (symbol: String, text: String, tint: Color)? = nil
}

// MARK: - Entrance animation

/// Drives a staggered entrance from a single animatable value, which is all iOS 14
/// gives us without hand-rolling `animatableData` per mark. Honours Reduce Motion.
struct ChartEntrance: ViewModifier {
    @Binding var t: Double
    let key: String
    var duration: Double = 0.85
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { run() }
            // Switching runs re-plays the entrance so a changed chart never looks stale.
            .onChange(of: key) { _ in t = 0; run() }
    }

    private func run() {
        guard !reduceMotion else { t = 1; return }
        t = 0
        withAnimation(.linear(duration: duration)) { t = 1 }
    }
}

extension View {
    func chartEntrance(_ t: Binding<Double>, key: String, duration: Double = 0.85) -> some View {
        modifier(ChartEntrance(t: t, key: key, duration: duration))
    }
}

/// Per-mark progress derived from the shared clock, so marks cascade instead of
/// all growing at once.
func markProgress(_ index: Int, count: Int, clock t: Double, stagger: Double = 0.5) -> Double {
    guard count > 1 else { return easeOut(t) }
    let start = stagger * Double(index) / Double(count - 1)
    let span = max(0.0001, 1 - stagger)
    return easeOut(min(1, max(0, (t - start) / span)))
}

func easeOut(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return 1 - pow(1 - c, 3)
}

// MARK: - Chart card

/// Chart chrome: title, subtitle, an optional table-view twin, and the legend slot.
/// Every chart ships a table so no value is reachable only by looking at colour.
struct ChartCard<Chart: View, Legend: View>: View {
    let title: String
    var subtitle: String? = nil
    var rows: [ChartDatum] = []
    @ViewBuilder var chart: () -> Chart
    @ViewBuilder var legend: () -> Legend

    @State private var showTable = false

    var body: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.cfHead(16)).foregroundColor(CF.title)
                        if let s = subtitle {
                            Text(s).font(.cfBody(12)).foregroundColor(CF.textSec)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if !rows.isEmpty {
                        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showTable.toggle() } }) {
                            Image(systemName: showTable ? "chart.bar.fill" : "tablecells")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(CF.blue)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibility(label: Text(showTable ? "Show chart" : "Show values as a table"))
                    }
                }

                if showTable {
                    tableView
                } else {
                    chart()
                    legend()
                }
            }
        }
    }

    private var tableView: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack {
                    Circle().fill(row.color).frame(width: 8, height: 8)
                    Text(row.label).font(.cfBody(13)).foregroundColor(CF.text)
                    Spacer()
                    Text(row.display)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(CF.title)
                }
                .padding(.vertical, 7)
                Divider().background(CF.divider)
            }
        }
    }
}

// MARK: - Empty state

struct ChartEmpty: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar").foregroundColor(CF.textMute)
            Text(text).font(.cfBody(12)).foregroundColor(CF.textMute)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 10).fill(CF.bg2))
    }
}

// MARK: - Legend

/// Swatch + name + value. The legend is the dependable identity channel; it is always
/// present for two or more series, and it carries the values that make the low-contrast
/// slots readable without relying on the fill.
struct ChartLegend: View {
    let items: [ChartDatum]
    var columns: Int = 2

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rowsOfItems, id: \.first?.id) { row in
                HStack(spacing: 12) {
                    ForEach(row) { item in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.color)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.label)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(CF.textSec)
                                    .lineLimit(1)
                                Text(item.display)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundColor(CF.title)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // keep the last row's columns aligned with the ones above
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var rowsOfItems: [[ChartDatum]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }
}

// MARK: - 1. Stacked part-to-whole bar

/// Horizontal stacked bar. Segments grow left-to-right off a single baseline, each
/// separated by a surface gap rather than a stroke.
struct StackedBarChart: View {
    let segments: [ChartDatum]
    let animationKey: String
    var height: CGFloat = Mark.barThickness

    @State private var t: Double = 0

    private var total: Double { max(segments.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(0, segments.count - 1)) * Mark.gap
            let usable = max(1, geo.size.width - gaps)
            HStack(spacing: Mark.gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                    let full = CGFloat(seg.value / total) * usable
                    let p = markProgress(i, count: segments.count, clock: t)
                    DataEnd.slice(Mark.radius, first: i == 0, last: i == segments.count - 1)
                        .fill(seg.color)
                        .frame(width: max(0.5, full * CGFloat(p)))
                }
                Spacer(minLength: 0)
            }
            .frame(height: height, alignment: .leading)
        }
        .frame(height: height)
        .chartEntrance($t, key: animationKey)
        .accessibilityElement()
        .accessibility(label: Text(summary))
    }

    private var summary: String {
        segments.map { "\($0.label) \($0.display)" }.joined(separator: ", ")
    }
}

// MARK: - 2. Range bars against a comfort band

/// Horizontal bars measured against an acceptable range — the work triangle's legs
/// against the 120–270 cm comfort band. The band is the baseline the reader compares
/// to, so it is drawn behind the marks rather than described in a caption.
struct ComfortBandChart: View {
    let bars: [ChartDatum]
    let bandLow: Double
    let bandHigh: Double
    let axisMax: Double
    let bandLabel: String
    let animationKey: String

    @State private var t: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (v: Double) -> CGFloat in CGFloat(min(1, max(0, v / axisMax))) * w }
                ZStack(alignment: .topLeading) {
                    // comfort band behind the marks
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CF.ok.opacity(0.10))
                        .frame(width: max(2, x(bandHigh) - x(bandLow)))
                        .offset(x: x(bandLow))
                    Rectangle().fill(CF.ok.opacity(0.35)).frame(width: Mark.hairline)
                        .offset(x: x(bandLow))
                    Rectangle().fill(CF.ok.opacity(0.35)).frame(width: Mark.hairline)
                        .offset(x: x(bandHigh))

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(bars.enumerated()), id: \.element.id) { i, bar in
                            let p = markProgress(i, count: bars.count, clock: t)
                            HStack(spacing: 8) {
                                DataEnd.bar(Mark.radius)
                                    .fill(bar.color)
                                    .frame(width: max(1, x(bar.value) * CGFloat(p)), height: 14)
                                Text(bar.display)
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundColor(CF.title)
                                    .opacity(p)
                                if let s = bar.status {
                                    HStack(spacing: 3) {
                                        Image(systemName: s.symbol).font(.system(size: 9, weight: .bold))
                                        Text(s.text).font(.system(size: 10, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(s.tint)
                                    .opacity(p)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(height: CGFloat(bars.count) * 26 + 4)

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(CF.ok.opacity(0.25))
                    .frame(width: 14, height: 8)
                Text(bandLabel).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(CF.textSec)
                Spacer(minLength: 0)
            }
        }
        .chartEntrance($t, key: animationKey)
    }
}

// MARK: - 3. Columns (ordinal ramp or emphasis)

/// Vertical columns growing from a shared baseline. Used two ways: an ordinal ramp
/// for ordered buckets, and emphasis (one accent column, the rest recessive) when the
/// story is "where does this one sit".
struct ColumnChart: View {
    let columns: [ChartDatum]
    let animationKey: String
    var height: CGFloat = 130
    /// Label under each column.
    var axisLabels: [String] = []
    /// Only the emphasised columns get a value on the cap — a number on every column
    /// stops being read.
    var labelEmphasisedOnly: Bool = false

    @State private var t: Double = 0

    private var maxValue: Double { max(columns.map(\.value).max() ?? 0, 0.0001) }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let n = max(1, columns.count)
                // Cap the band so a two-bucket chart clusters in the middle instead of
                // pinning one column to each far corner.
                let band = min(96, geo.size.width / CGFloat(n))
                let barW = min(Mark.barThickness, max(6, band - 8))
                ZStack(alignment: .bottom) {
                    // recessive baseline
                    Rectangle().fill(CFChart.grid).frame(height: Mark.hairline)

                    HStack(alignment: .bottom, spacing: 0) {
                        Spacer(minLength: 0)
                        ForEach(Array(columns.enumerated()), id: \.element.id) { i, col in
                            let p = markProgress(i, count: columns.count, clock: t)
                            let full = CGFloat(col.value / maxValue) * (geo.size.height - 18)
                            VStack(spacing: 3) {
                                if !labelEmphasisedOnly || col.isEmphasised {
                                    Text(col.display)
                                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .foregroundColor(CF.title)
                                        .lineLimit(1).minimumScaleFactor(0.6)
                                        .opacity(p)
                                }
                                DataEnd.column(Mark.radius)
                                    .fill(col.color)
                                    .frame(width: barW, height: max(2, full * CGFloat(p)))
                            }
                            .frame(width: band)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: height)

            if !axisLabels.isEmpty {
                GeometryReader { geo in
                    let band = min(96, geo.size.width / CGFloat(max(1, axisLabels.count)))
                    HStack(spacing: 0) {
                        ForEach(Array(axisLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(CF.textMute)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(width: band)
                        }
                    }
                    .frame(width: geo.size.width)
                }
                .frame(height: 14)
            }
        }
        .chartEntrance($t, key: animationKey)
    }
}

// MARK: - 4. Readiness meter

/// A single ratio against a limit. The fill carries severity; the track is a lighter
/// step of the same ramp so the state reads even in greyscale.
struct ReadinessMeter: View {
    let progress: Double
    let caption: String
    let animationKey: String

    @State private var t: Double = 0

    private var tint: Color {
        if progress >= 0.999 { return CF.ok }
        if progress >= 0.6 { return CF.blue }
        return CF.warn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int((progress * easeOut(t) * 100).rounded()))")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(CF.title)
                Text("% ready").font(.cfBody(13)).foregroundColor(CF.textSec)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CFChart.track)
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(progress * easeOut(t))))
                }
            }
            .frame(height: 10)
            Text(caption).font(.cfBody(12)).foregroundColor(CF.textSec)
                .fixedSize(horizontal: false, vertical: true)
        }
        .chartEntrance($t, key: animationKey)
        .accessibilityElement()
        .accessibility(label: Text("Readiness \(Int((progress * 100).rounded())) percent. \(caption)"))
    }
}
