//
//  ReportsViews.swift
//  CabFit
//
//  Output screens: Spec list, Cost estimate, Layout board, Order sheet,
//  Approval & Reports, the Reports tab, and the PDF exporter.
//

import SwiftUI

// MARK: - Spec aggregation model

/// Which part of the order a line belongs to. The order sheet used to sort lines by
/// matching substrings of their display names, which broke the moment a name changed.
enum SpecGroup: String, CaseIterable, Identifiable {
    case modules, fronts, hardware, niches
    var id: String { rawValue }
    var title: String {
        switch self {
        case .modules:  return "Modules"
        case .fronts:   return "Fronts & Fillers"
        case .hardware: return "Hardware"
        case .niches:   return "Appliance Niches"
        }
    }
}

struct SpecLine: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let qty: Int
    var group: SpecGroup = .modules
}

extension KitchenRun {
    /// Aggregated bill of modules / fronts / fillers / hardware / niches.
    var specLines: [SpecLine] {
        var lines: [SpecLine] = []
        let cabinets = units.filter { $0.type != .wall }
        let wallU = units.filter { $0.type == .wall }

        // Group base/tall units by function + width so the supplier gets quantities.
        var grouped: [String: (CabinetUnit, Int)] = [:]
        for u in cabinets {
            let key = "\(u.function.title)-\(Int(u.widthCM))-\(u.type.rawValue)"
            if let g = grouped[key] { grouped[key] = (g.0, g.1 + 1) } else { grouped[key] = (u, 1) }
        }
        for (_, g) in grouped.sorted(by: { $0.value.0.widthCM > $1.value.0.widthCM }) {
            lines.append(SpecLine(name: g.0.function.title,
                                  detail: "\(Int(g.0.widthCM)) cm \(g.0.type.title.lowercased())",
                                  qty: g.1, group: .modules))
        }
        if !wallU.isEmpty {
            var wallGrouped: [Int: Int] = [:]
            for u in wallU { wallGrouped[Int(u.widthCM), default: 0] += 1 }
            for (w, n) in wallGrouped.sorted(by: { $0.key > $1.key }) {
                lines.append(SpecLine(name: "Wall unit", detail: "\(w) cm × 35 cm deep",
                                      qty: n, group: .modules))
            }
        }

        // Fronts: a drawer bank ships three fronts, an open shelf none.
        if doorFrontCount > 0 {
            lines.append(SpecLine(name: "Doors", detail: "hinged fronts",
                                  qty: doorFrontCount, group: .fronts))
        }
        if drawerFrontCount > 0 {
            lines.append(SpecLine(name: "Drawer fronts", detail: "3 per drawer bank",
                                  qty: drawerFrontCount, group: .fronts))
        }
        if !fillers.isEmpty {
            lines.append(SpecLine(name: "Filler strips",
                                  detail: fillers.map { String(format: "%.0f", $0.widthCM) }.joined(separator: ", ") + " cm",
                                  qty: fillers.count, group: .fronts))
        }

        // Hardware: doors take hinges, drawer banks take runner pairs. Counting a
        // drawer bank as "two hinges" put the wrong parts on the order.
        if doorFrontCount > 0 {
            lines.append(SpecLine(name: "Hinges", detail: "soft-close, 2 per door",
                                  qty: doorFrontCount * 2, group: .hardware))
        }
        if drawerBankCount > 0 {
            lines.append(SpecLine(name: "Drawer runner sets", detail: "soft-close, 3 per bank",
                                  qty: drawerBankCount * 3, group: .hardware))
        }
        if frontCount > 0 {
            lines.append(SpecLine(name: "Handles", detail: handleType,
                                  qty: handleType == "Push-to-open" ? 0 : frontCount, group: .hardware))
        }
        if legsAdjustable && !cabinets.isEmpty {
            lines.append(SpecLine(name: "Adjustable legs",
                                  detail: "\(Int(plinthHeightCM)) cm plinth, 4 per carcass",
                                  qty: cabinets.count * 4, group: .hardware))
        }
        if plinthRunMetres > 0 {
            lines.append(SpecLine(name: "Plinth board",
                                  detail: String(format: "%.1f m at %d cm high", plinthRunMetres, Int(plinthHeightCM)),
                                  qty: Int(plinthRunMetres.rounded(.up)), group: .hardware))
        }
        if worktopRunMetres > 0 {
            lines.append(SpecLine(name: "Worktop",
                                  detail: String(format: "%@, %.1f m × %d cm", worktopMaterial, worktopRunMetres, Int(worktopDepthCM)),
                                  qty: Int(worktopRunMetres.rounded(.up)), group: .hardware))
        }
        if splashbackHeightCM > 0 && worktopRunMetres > 0 {
            lines.append(SpecLine(name: "Splashback",
                                  detail: String(format: "%.1f m × %d cm high", worktopRunMetres, Int(splashbackHeightCM)),
                                  qty: Int(worktopRunMetres.rounded(.up)), group: .hardware))
        }

        for a in appliances {
            var services: [String] = []
            if a.hasWater { services.append("water") }
            if a.hasPower { services.append("power") }
            let svc = services.isEmpty ? "no services" : services.joined(separator: " + ")
            lines.append(SpecLine(name: a.kind.title + " niche",
                                  detail: "\(Int(a.slotWidthCM)) cm + \(fmtCM(a.clearanceCM))×2 clearance, \(svc)",
                                  qty: 1, group: .niches))
        }
        return lines
    }

    private func fmtCM(_ v: Double) -> String {
        abs(v.rounded() - v) < 0.05 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    func specLines(in group: SpecGroup) -> [SpecLine] { specLines.filter { $0.group == group } }

    // MARK: Counts

    var drawerBankCount: Int { units.filter { $0.function == .drawers }.count }
    var drawerFrontCount: Int { drawerBankCount * 3 }
    /// Units that get a hinged door — open shelves and drawer banks don't.
    var doorFrontCount: Int {
        units.filter { $0.function != .openShelf && $0.function != .drawers }.count
    }
    var frontCount: Int { doorFrontCount + drawerFrontCount }
    var cabinetCount: Int { units.count }
    var worktopRunMetres: Double { (baseUnitsTotalCM + applianceTotalCM + fillersTotalCM) / 100 }
    var plinthRunMetres: Double { (baseUnitsTotalCM + fillersTotalCM) / 100 }

    func cabinetsCost() -> Double { Double(cabinetCount) * pricePerCabinet }
    func frontsCost() -> Double { Double(frontCount) * pricePerFront }
    func worktopCost() -> Double { worktopRunMetres * pricePerWorktopMetre }
    func subtotal() -> Double { cabinetsCost() + frontsCost() + worktopCost() }
    func reserveAmount() -> Double { subtotal() * reservePercent / 100 }
    func totalCost() -> Double { subtotal() + reserveAmount() }

    // MARK: CSV

    /// Comma-separated bill of materials — most suppliers want a sheet, not a PDF.
    var specCSV: String {
        var rows = ["Group,Item,Detail,Qty"]
        for line in specLines {
            rows.append([line.group.title, line.name, line.detail, "\(line.qty)"]
                            .map(KitchenRun.csvEscape).joined(separator: ","))
        }
        rows.append("")
        rows.append(["Summary", "Run", title, ""].map(KitchenRun.csvEscape).joined(separator: ","))
        rows.append(["Summary", "Shape", shape.title, ""].map(KitchenRun.csvEscape).joined(separator: ","))
        rows.append(["Summary", "Wall length", String(format: "%.0f cm", totalWallCM), ""].map(KitchenRun.csvEscape).joined(separator: ","))
        rows.append(["Summary", "Total", currency + String(format: "%.0f", totalCost()), ""].map(KitchenRun.csvEscape).joined(separator: ","))
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - 13 Spec & Material List

struct SpecListView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Spec & Material List",
                       subtitle: "Full unit and material list.",
                       toast: $toast) {
            CFCard {
                HStack(spacing: 10) {
                    MetricBadge(value: "\(run.cabinetCount)", label: "Units", hex: "1F6FE0")
                    MetricBadge(value: "\(run.frontCount)", label: "Fronts", hex: "F77A1E")
                    MetricBadge(value: "\(run.fillers.count)", label: "Fillers", hex: "F6BE24")
                    MetricBadge(value: "\(run.appliances.count)", label: "Niches", hex: "2FA85A")
                }
            }
            CFCard {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(icon: "list.bullet", title: "Bill of Materials")
                        .padding(.bottom, 8)
                    if run.specLines.isEmpty {
                        Text("Add units to build the spec.").font(.cfBody(13)).foregroundColor(CF.textMute)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(run.specLines) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.name).font(.cfHead(14)).foregroundColor(CF.title)
                                    Text(line.detail).font(.cfBody(11)).foregroundColor(CF.textSec)
                                }
                                Spacer()
                                Text("×\(line.qty)").font(.cfNum(15)).foregroundColor(CF.blue)
                            }
                            .padding(.vertical, 7)
                            Divider().background(CF.divider)
                        }
                    }
                }
            }
            Button(action: { settings.haptic(.medium); cfFlash($toast, "List built") }) {
                HStack { Image(systemName: "checkmark"); Text("Build List") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Cost Estimate", icon: "dollarsign.circle.fill",
                          destination: CostEstimateView(run: $run))
        }
    }
}

// MARK: - 14 Cost Estimate

struct CostEstimateView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil
    private let currencies = ["$", "€", "£", "₽", "zł"]

    var body: some View {
        EngineScaffold(title: "Cost Estimate",
                       subtitle: "Add up cabinets, fronts and hardware.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 0) {
                    costRow("Cabinets", "\(run.cabinetCount) × \(run.currency)\(Int(run.pricePerCabinet))", run.cabinetsCost())
                    Divider().background(CF.divider)
                    costRow("Fronts", "\(run.frontCount) × \(run.currency)\(Int(run.pricePerFront))", run.frontsCost())
                    Divider().background(CF.divider)
                    costRow("Worktop", String(format: "%.1f m × %@%d", run.worktopRunMetres, run.currency, Int(run.pricePerWorktopMetre)), run.worktopCost())
                    Divider().background(CF.divider)
                    costRow("Reserve", "\(Int(run.reservePercent))%", run.reserveAmount())
                    Divider().background(CF.divider).padding(.vertical, 2)
                    HStack {
                        Text("Total").font(.cfHead(17)).foregroundColor(CF.title)
                        Spacer()
                        Text(run.currency + String(format: "%.0f", run.totalCost()))
                            .font(.cfNum(22)).foregroundColor(CF.orange)
                    }.padding(.top, 6)
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "slider.horizontal.3", title: "Rates")
                    CFStepperRow(label: "Per cabinet", value: $run.pricePerCabinet, step: 10, range: 0...2000, kind: .raw(run.currency))
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Per front", value: $run.pricePerFront, step: 5, range: 0...1000, kind: .raw(run.currency))
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Worktop / m", value: $run.pricePerWorktopMetre, step: 10, range: 0...2000, kind: .raw(run.currency))
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Reserve", value: $run.reservePercent, step: 1, range: 0...40, kind: .raw("%"))
                    miniLabel2("Currency")
                    HStack(spacing: 8) {
                        ForEach(currencies, id: \.self) { c in
                            Button(action: { run.currency = c }) {
                                OptionChip(title: c, selected: run.currency == c)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            Button(action: { settings.haptic(.medium); cfFlash($toast, "Total " + run.currency + String(format: "%.0f", run.totalCost())) }) {
                HStack { Image(systemName: "equal.circle.fill"); Text("Calculate Cost") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Layout Board", icon: "square.grid.2x2.fill",
                          destination: LayoutBoardView(run: $run))
        }
    }

    private func costRow(_ name: String, _ detail: String, _ value: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.cfHead(14)).foregroundColor(CF.title)
                Text(detail).font(.cfBody(11)).foregroundColor(CF.textSec)
            }
            Spacer()
            Text(run.currency + String(format: "%.0f", value)).font(.cfNum(15)).foregroundColor(CF.blue)
        }.padding(.vertical, 8)
    }
    private func miniLabel2(_ s: String) -> some View {
        HStack { Text(s.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(CF.textMute); Spacer() }
    }
}

// MARK: - 15 Layout Board

struct LayoutBoardView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var showTriangle = true
    @State private var showAppliances = true
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Layout Board",
                       subtitle: "See the whole kitchen in one plan.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 10) {
                    Text("Elevation").font(.cfBody(11)).foregroundColor(CF.textMute)
                    WallElevationStack(run: run, overHood: run.hoodGap).frame(height: 160)
                    Divider().background(CF.divider)
                    Text("Top plan").font(.cfBody(11)).foregroundColor(CF.textMute)
                    PlanBoard(run: run, showTriangle: showTriangle, showAppliances: showAppliances)
                        .frame(height: 180)
                }
            }
            CFCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "square.grid.2x2.fill", title: "Items")
                    Toggle(isOn: $showTriangle) { Text("Show work triangle").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.orange))
                    Toggle(isOn: $showAppliances) { Text("Show appliances").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                    CFTextField(label: "Notes", text: $run.notes, placeholder: "Plan notes for the fitter")
                }
            }
            Button(action: { settings.haptic(.medium); cfFlash($toast, "Layout saved") }) {
                HStack { Image(systemName: "checkmark"); Text("Keep Layout") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Order Sheet", icon: "doc.text.fill",
                          destination: OrderSheetView(run: $run))
        }
    }
}

struct PlanBoard: View {
    let run: KitchenRun
    let showTriangle: Bool
    let showAppliances: Bool
    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(CF.bg2)
                RoundedRectangle(cornerRadius: 12).stroke(CF.border, lineWidth: 1)
                // base run along bottom
                let denom = max(run.totalWallCM, 1)
                HStack(spacing: 2) {
                    ForEach(run.units.filter { $0.type != .wall }) { u in
                        RoundedRectangle(cornerRadius: 3).fill(CF.blue)
                            .frame(width: CGFloat(u.widthCM / denom) * (s.width - 40), height: 26)
                    }
                    if showAppliances {
                        ForEach(run.appliances) { a in
                            RoundedRectangle(cornerRadius: 3).stroke(CF.orange, lineWidth: 2)
                                .frame(width: CGFloat(a.totalWidthCM / denom) * (s.width - 40), height: 26)
                        }
                    }
                }
                .position(x: s.width/2, y: s.height - 26)

                if showTriangle {
                    Path { p in
                        p.move(to: pt(run.triangle.sink, s)); p.addLine(to: pt(run.triangle.hob, s))
                        p.addLine(to: pt(run.triangle.fridge, s)); p.closeSubpath()
                    }.stroke(CF.orange, style: StrokeStyle(lineWidth: 2, dash: [5,3]))
                    dot(run.triangle.sink, s, CF.blue)
                    dot(run.triangle.hob, s, CF.orange)
                    dot(run.triangle.fridge, s, CF.blueAct)
                }
            }
        }
    }
    private func pt(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * (s.width - 40) + 20, y: CGFloat(p.y) * (s.height - 60) + 14)
    }
    private func dot(_ p: CGPoint, _ s: CGSize, _ c: Color) -> some View {
        Circle().fill(c).frame(width: 14, height: 14).position(pt(p, s))
    }
}

// MARK: - 18 Order Sheet 🔥

struct OrderSheetView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil
    @State private var shareURL: URL? = nil
    @State private var showShare = false

    /// `specLines` regroups the whole run each time it is read; read it once.
    private var lines: [SpecLine] { run.specLines }

    var body: some View {
        EngineScaffold(title: "Order Sheet",
                       subtitle: "Build the order for cabinets and fronts.",
                       toast: $toast) {
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ORDER • \(run.title)").font(.cfHead(15)).foregroundColor(CF.title)
                            Text(run.shape.title + " • " + run.moduleStandard.title)
                                .font(.cfBody(11)).foregroundColor(CF.textSec)
                        }
                        Spacer()
                        StatusPill(text: run.status.title, hex: run.status.hex)
                    }
                    WallStripView(run: run, height: 56)
                }
            }

            ForEach(SpecGroup.allCases) { group in
                orderGroup(group.title, lines.filter { $0.group == group })
            }

            CFCard {
                CFTextField(label: "Notes", text: $run.notes, placeholder: "Delivery / finish notes")
            }

            if run.blockerCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill").foregroundColor(CF.danger)
                    Text("\(run.blockerCount) blocker\(run.blockerCount == 1 ? "" : "s") on this run — see Checks in Run Detail.")
                        .font(.cfBody(12)).foregroundColor(CF.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(CF.danger.opacity(0.12)))
            }

            Button(action: { settings.haptic(.medium); run.status = .ready; cfFlash($toast, "Order marked ready") }) {
                HStack { Image(systemName: "checkmark"); Text("Build Order") }
            }.buttonStyle(ActionButtonStyle())

            HStack(spacing: 10) {
                Button(action: exportPDF) {
                    HStack { Image(systemName: "doc.richtext"); Text("PDF") }
                }.buttonStyle(SecondaryButtonStyle())
                Button(action: exportCSV) {
                    HStack { Image(systemName: "tablecells"); Text("CSV") }
                }.buttonStyle(GhostButtonStyle())
            }

            EngineNavLink(title: "Open Approval", icon: "checkmark.seal.fill",
                          destination: ApprovalReportView(run: $run))
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ActivityView(items: [url]) }
        }
    }

    private func orderGroup(_ title: String, _ lines: [SpecLine]) -> some View {
        Group {
            if !lines.isEmpty {
                CFCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(CF.textMute).padding(.bottom, 6)
                        ForEach(lines) { l in
                            HStack {
                                Text(l.name).font(.cfHead(13)).foregroundColor(CF.title)
                                Text(l.detail).font(.cfBody(11)).foregroundColor(CF.textSec)
                                Spacer()
                                Text("×\(l.qty)").font(.cfNum(14)).foregroundColor(CF.blue)
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }

    private func exportPDF() {
        settings.haptic(.medium)
        if let url = PDFExporter.orderSheet(run: run) {
            shareURL = url
            showShare = true
        } else {
            cfFlash($toast, "Export failed")
        }
    }

    private func exportCSV() {
        settings.haptic(.medium)
        if let url = FileExporter.csv(run.specCSV, name: "CabFit-Order-" + FileExporter.safeName(run.title)) {
            shareURL = url
            showShare = true
        } else {
            cfFlash($toast, "Export failed")
        }
    }
}

// MARK: - 19 Approval & Reports

struct ApprovalReportView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var includeLayout = true
    @State private var includeSpec = true
    @State private var includeCost = true
    @State private var clearSignatureToken = 0
    @State private var toast: String? = nil
    @State private var shareURL: URL? = nil
    @State private var showShare = false
    @State private var confirmApproveWithBlockers = false

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        EngineScaffold(title: "Approval & Reports",
                       subtitle: "Approve and export a clean report.",
                       toast: $toast) {
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "checkmark.seal.fill", title: "Sign-off")
                    CFTextField(label: "Reviewer", text: $run.reviewer, placeholder: "Name")
                    miniLabel3("Decision")
                    HStack(spacing: 8) {
                        ForEach(["Approved", "Changes", "Rejected"], id: \.self) { d in
                            Button(action: { settings.haptic(); run.reviewDecision = d }) {
                                OptionChip(title: d, selected: run.reviewDecision == d,
                                           accent: d == "Approved" ? CF.ok : (d == "Rejected" ? CF.danger : CF.warn))
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    miniLabel3("Signature")
                    SignaturePad(signature: $run.signature, clearToken: clearSignatureToken)
                    Button(action: {
                        settings.haptic()
                        run.signature = nil
                        // Bumping the token also clears the strokes the pad is still
                        // drawing — clearing only the data left the ink on screen.
                        clearSignatureToken += 1
                    }) {
                        HStack { Image(systemName: "xmark"); Text("Clear Signature") }
                    }.buttonStyle(GhostButtonStyle())

                    if let stamp = run.reviewDate {
                        Text("Last decision: \(run.reviewDecision) • \(ApprovalReportView.stampFormatter.string(from: stamp))")
                            .font(.cfBody(11)).foregroundColor(CF.textMute)
                    }
                }
            }

            if run.blockerCount > 0 {
                CFCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(icon: "xmark.octagon.fill", title: "Blocking checks",
                                      subtitle: "Fix these before signing off")
                        ForEach(run.issues.filter { $0.level == .blocker }) { issue in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(CF.danger).frame(width: 6, height: 6).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.title).font(.cfHead(13)).foregroundColor(CF.title)
                                    Text(issue.detail).font(.cfBody(12)).foregroundColor(CF.textSec)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "doc.text.fill", title: "Include Sections")
                    Toggle(isOn: $includeLayout) { Text("Layout, wall strip & photo").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                    Toggle(isOn: $includeSpec) { Text("Spec & materials").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                    Toggle(isOn: $includeCost) { Text("Cost estimate").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                }
            }

            Button(action: approveTapped) {
                HStack { Image(systemName: "checkmark.seal.fill"); Text(approveLabel) }
            }.buttonStyle(ActionButtonStyle())

            HStack(spacing: 10) {
                Button(action: exportPDF) {
                    HStack { Image(systemName: "doc.richtext"); Text("Report PDF") }
                }.buttonStyle(PrimaryButtonStyle())
                Button(action: exportCSV) {
                    HStack { Image(systemName: "tablecells"); Text("CSV") }
                }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .alert(isPresented: $confirmApproveWithBlockers) {
            Alert(title: Text("Approve with \(run.blockerCount) blocker\(run.blockerCount == 1 ? "" : "s")?"),
                  message: Text("The run doesn't pass its own checks yet. You can approve anyway, but the report will list them."),
                  primaryButton: .destructive(Text("Approve anyway")) { commitDecision() },
                  secondaryButton: .cancel())
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ActivityView(items: [url]) }
        }
    }

    private var approveLabel: String {
        run.reviewDecision == "Approved" ? "Approve Run" : "Record \(run.reviewDecision)"
    }

    private func approveTapped() {
        if run.reviewDecision == "Approved" && run.blockerCount > 0 {
            confirmApproveWithBlockers = true
        } else {
            commitDecision()
        }
    }

    private func commitDecision() {
        settings.haptic(.heavy)
        run.approved = (run.reviewDecision == "Approved")
        run.reviewDate = Date()
        if run.approved { run.status = .approved }
        else if run.status == .approved { run.status = .inProgress }
        cfFlash($toast, run.approved ? "Run approved" : "Decision saved")
    }

    private func exportPDF() {
        settings.haptic(.medium)
        if let url = PDFExporter.report(run: run, decision: run.reviewDecision,
                                        includeLayout: includeLayout, includeSpec: includeSpec,
                                        includeCost: includeCost) {
            shareURL = url; showShare = true
        } else { cfFlash($toast, "Export failed") }
    }

    private func exportCSV() {
        settings.haptic(.medium)
        if let url = FileExporter.csv(run.specCSV, name: "CabFit-Spec-" + FileExporter.safeName(run.title)) {
            shareURL = url; showShare = true
        } else { cfFlash($toast, "Export failed") }
    }

    private func miniLabel3(_ s: String) -> some View {
        HStack { Text(s.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(CF.textMute); Spacer() }
    }
}

// MARK: - Signature pad

struct SignaturePad: View {
    @Binding var signature: Data?
    /// Bumped by the owner to wipe the live strokes as well as the stored image.
    var clearToken: Int = 0

    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(CF.bg2)
            RoundedRectangle(cornerRadius: 12).stroke(CF.border, lineWidth: 1)
            if let data = signature, let ui = UIImage(data: data), strokes.isEmpty {
                Image(uiImage: ui).resizable().scaledToFit().padding(8)
            }
            // live strokes
            ForEach(0..<strokes.count, id: \.self) { i in strokePath(strokes[i]) }
            strokePath(current)
            if signature == nil && strokes.isEmpty {
                Text("Sign here").font(.cfBody(13)).foregroundColor(CF.textMute)
            }
        }
        .frame(height: 130)
        .background(GeometryReader { g in Color.clear.onAppear { canvasSize = g.size }
            .onChange(of: g.size) { canvasSize = $0 } })
        .onChange(of: clearToken) { _ in strokes = []; current = [] }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in current.append(v.location) }
            .onEnded { _ in
                if !current.isEmpty { strokes.append(current); current = [] }
                rasterize()
            })
    }

    private func strokePath(_ pts: [CGPoint]) -> some View {
        Path { p in
            guard let f = pts.first else { return }
            p.move(to: f)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }.stroke(CF.title, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func rasterize() {
        guard canvasSize.width > 0 else { return }
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            ctx.cgContext.setStrokeColor(UIColor(hexString: "102A4A").cgColor)
            ctx.cgContext.setLineWidth(2.5)
            ctx.cgContext.setLineCap(.round)
            for stroke in strokes {
                guard let f = stroke.first else { continue }
                ctx.cgContext.move(to: f)
                for pt in stroke.dropFirst() { ctx.cgContext.addLine(to: pt) }
                ctx.cgContext.strokePath()
            }
        }
        signature = img.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Reports tab

struct ReportsTab: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings
    @State private var shareURL: URL? = nil
    @State private var showShare = false

    var body: some View {
        NavigationView {
            ZStack {
                CF.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        TabTitleHeader(title: "Reports", subtitle: "Spec, cost, order and approval")
                        RunPickerBar()

                        if let binding = store.selectedBinding {
                            let run = binding.wrappedValue

                            headline(run)
                            costChart(run)
                            triangleChart(run)
                            moduleMixChart(run)
                            portfolioChart(run)

                            sectionLabel("Detail")
                            NavigationLink(destination: SpecListView(run: binding)) {
                                actionRow("Spec & Material List", "Full unit and material list", "list.bullet")
                            }.buttonStyle(PlainButtonStyle())
                            NavigationLink(destination: CostEstimateView(run: binding)) {
                                actionRow("Cost Estimate", "Cabinets, fronts and hardware", "dollarsign.circle.fill")
                            }.buttonStyle(PlainButtonStyle())
                            NavigationLink(destination: OrderSheetView(run: binding)) {
                                actionRow("Order Sheet", "Build the supplier order", "doc.text.fill")
                            }.buttonStyle(PlainButtonStyle())
                            NavigationLink(destination: ApprovalReportView(run: binding)) {
                                actionRow("Approval & Reports", "Sign off and export PDF", "checkmark.seal.fill")
                            }.buttonStyle(PlainButtonStyle())

                            sectionLabel("Export")
                            Button(action: { exportFull(run) }) {
                                HStack { Image(systemName: "doc.richtext"); Text("Export Full Report PDF") }
                            }.buttonStyle(ActionButtonStyle())
                            Button(action: { exportCSV(run) }) {
                                HStack { Image(systemName: "tablecells"); Text("Export Spec as CSV") }
                            }.buttonStyle(GhostButtonStyle())
                        } else {
                            NoRunEmptyState(message: "Create a run in the Runs tab to build reports and the order sheet.")
                                .frame(height: 320)
                        }
                        TabBottomSpacer()
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ActivityView(items: [url]) }
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(CF.textMute)
            .padding(.top, 4)
    }

    // MARK: Headline — the number the tab leads with, plus the readiness meter

    private func headline(_ run: KitchenRun) -> some View {
        CFCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated total")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(CF.textSec)
                    Text(run.currency + String(format: "%.0f", run.totalCost()))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(CF.title)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("\(run.cabinetCount) units · \(run.frontCount) fronts · \(String(format: "%.1f", run.worktopRunMetres)) m worktop")
                        .font(.cfBody(12)).foregroundColor(CF.textSec)
                }
                Divider().background(CF.divider)
                ReadinessMeter(progress: run.readiness,
                               caption: readinessCaption(run),
                               animationKey: run.id.uuidString)
            }
        }
    }

    private func readinessCaption(_ run: KitchenRun) -> String {
        if run.blockerCount > 0 {
            return "\(run.blockerCount) blocker\(run.blockerCount == 1 ? "" : "s") to clear before ordering."
        }
        let steps = run.readinessSteps
        if let next = steps.first(where: { !$0.done }) {
            return "Next: \(next.title.lowercased())."
        }
        return "Every check is done — this run is ready to order."
    }

    // MARK: Cost breakdown — part-to-whole

    private func costChart(_ run: KitchenRun) -> some View {
        let segs: [ChartDatum] = [
            ChartDatum(label: "Cabinets", value: run.cabinetsCost(),
                       display: money(run, run.cabinetsCost()), color: CFChart.categorical(0)),
            ChartDatum(label: "Fronts", value: run.frontsCost(),
                       display: money(run, run.frontsCost()), color: CFChart.categorical(1)),
            ChartDatum(label: "Worktop", value: run.worktopCost(),
                       display: money(run, run.worktopCost()), color: CFChart.categorical(2)),
            ChartDatum(label: "Reserve", value: run.reserveAmount(),
                       display: money(run, run.reserveAmount()), color: CFChart.categorical(3))
        ].filter { $0.value > 0 }

        return ChartCard(title: "Where the money goes",
                         subtitle: "Share of the \(money(run, run.totalCost())) estimate",
                         rows: segs) {
            if segs.isEmpty {
                ChartEmpty(text: "Set rates in Cost Estimate to see the split.")
            } else {
                StackedBarChart(segments: segs, animationKey: costKey(run))
            }
        } legend: {
            if segs.isEmpty { EmptyView() } else { ChartLegend(items: segs) }
        }
    }

    // MARK: Work triangle — legs against the comfort band

    private func triangleChart(_ run: KitchenRun) -> some View {
        let t = run.scaledTriangle
        let legs: [(String, Double)] = [
            ("Sink → Hob", t.legSinkHob),
            ("Hob → Fridge", t.legHobFridge),
            ("Fridge → Sink", t.legFridgeSink)
        ]
        let bars: [ChartDatum] = legs.map { name, cm in
            // Colour here means good/bad, so it is a status colour — and it always
            // ships with an icon and a word, never on its own.
            let short = cm < 120, long = cm > 270
            let status: (String, String, Color)? = short
                ? ("arrow.down.right.and.arrow.up.left", "tight", CF.warn)
                : (long ? ("arrow.up.left.and.arrow.down.right", "long", CF.orange) : nil)
            return ChartDatum(label: name, value: cm, display: settings.len(cm),
                              color: (short || long) ? CF.warn : CFChart.categorical(0),
                              status: status)
        }
        let axisMax = max(300, (legs.map(\.1).max() ?? 0) * 1.15)
        let rating = t.rating

        return ChartCard(title: "Work triangle",
                         subtitle: "\(rating.title) · total walk \(settings.len(t.sum))",
                         rows: bars) {
            if run.units.isEmpty && run.appliances.isEmpty {
                ChartEmpty(text: "Place the sink, hob and fridge to measure the triangle.")
            } else {
                ComfortBandChart(bars: bars, bandLow: 120, bandHigh: 270, axisMax: axisMax,
                                 bandLabel: "Comfortable leg: \(settings.len(120))–\(settings.len(270))",
                                 animationKey: triangleKey(run))
            }
        } legend: {
            EmptyView()   // one series; the title says what is plotted
        }
    }

    // MARK: Module mix — ordered width buckets

    private func moduleMixChart(_ run: KitchenRun) -> some View {
        let widths = Dictionary(grouping: run.units.filter { $0.type != .wall }) { Int($0.widthCM.rounded()) }
            .map { (width: $0.key, count: $0.value.count) }
            .sorted { $0.width < $1.width }

        let cols: [ChartDatum] = widths.enumerated().map { i, w in
            ChartDatum(label: settings.len(Double(w.width)),
                       value: Double(w.count),
                       display: "\(w.count)",
                       color: CFChart.ordinalStep(i, of: widths.count))
        }
        let labels = widths.map { settings.lenValue(Double($0.width)) }

        return ChartCard(title: "Module mix",
                         subtitle: "How many carcasses of each width to order",
                         rows: cols) {
            if cols.isEmpty {
                ChartEmpty(text: "Build the run to see which module widths it needs.")
            } else {
                ColumnChart(columns: cols, animationKey: mixKey(run), axisLabels: labels)
            }
        } legend: {
            if cols.isEmpty {
                EmptyView()
            } else {
                Text("Width in \(settings.units.short), narrow to wide")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(CF.textMute)
            }
        }
    }

    // MARK: Portfolio — this run against the others

    private func portfolioChart(_ run: KitchenRun) -> some View {
        // Emphasis, not eight hues: the selected run is the point, the rest are context.
        let others = store.runs.sorted { $0.dateCreated < $1.dateCreated }
        let cols: [ChartDatum] = others.map { r in
            let selected = r.id == run.id
            return ChartDatum(label: r.title,
                              value: r.totalCost(),
                              display: money(r, r.totalCost()),
                              color: selected ? CFChart.categorical(0) : CFChart.deemphasis,
                              isEmphasised: selected)
        }

        return Group {
            if others.count >= 2 {
                ChartCard(title: "Against your other runs",
                          subtitle: "Estimated total per run, oldest first",
                          rows: cols) {
                    ColumnChart(columns: cols, animationKey: portfolioKey,
                                height: 120,
                                axisLabels: others.map { shortTitle($0.title) },
                                labelEmphasisedOnly: true)
                } legend: {
                    HStack(spacing: 12) {
                        legendKey(CFChart.categorical(0), run.title)
                        legendKey(CFChart.deemphasis, "Other runs")
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func legendKey(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(CF.textSec).lineLimit(1)
        }
    }

    private func shortTitle(_ s: String) -> String {
        s.count <= 8 ? s : String(s.prefix(7)) + "…"
    }

    private func money(_ run: KitchenRun, _ v: Double) -> String {
        run.currency + String(format: "%.0f", v)
    }

    // Animation keys — replay the entrance when the numbers behind a chart change,
    // not on every unrelated redraw.
    private func costKey(_ run: KitchenRun) -> String {
        "\(run.id)-\(Int(run.totalCost()))-\(run.cabinetCount)-\(run.frontCount)"
    }
    private func triangleKey(_ run: KitchenRun) -> String {
        "\(run.id)-\(Int(run.scaledTriangle.sum))"
    }
    private func mixKey(_ run: KitchenRun) -> String {
        "\(run.id)-\(run.units.count)-\(Int(run.baseUnitsTotalCM))-\(settings.units.rawValue)"
    }
    private var portfolioKey: String {
        "\(store.runs.count)-\(store.selectedRunID?.uuidString ?? "")"
    }

    private func exportFull(_ run: KitchenRun) {
        settings.haptic(.medium)
        let decision = run.reviewDate == nil ? "Draft" : run.reviewDecision
        if let url = PDFExporter.report(run: run, decision: decision,
                                        includeLayout: true, includeSpec: true, includeCost: true) {
            shareURL = url; showShare = true
        }
    }

    private func exportCSV(_ run: KitchenRun) {
        settings.haptic(.medium)
        if let url = FileExporter.csv(run.specCSV, name: "CabFit-Spec-" + FileExporter.safeName(run.title)) {
            shareURL = url; showShare = true
        }
    }
}

// MARK: - PDF exporter

enum PDFExporter {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72dpi
    private static let margin: CGFloat = 40

    enum Block {
        case title(String)
        case heading(String)
        case row(String, String)
        case note(String)
        case spacer(CGFloat)
        case divider
        case image(Data, maxHeight: CGFloat)
    }

    static func orderSheet(run: KitchenRun) -> URL? {
        var blocks: [Block] = [
            .title("Cab Fit — Order Sheet"),
            .row("Run", run.title),
            .row("Shape", run.shape.title),
            .row("Module standard", run.moduleStandard.title),
            .row("Wall length", String(format: "%.0f cm", run.totalWallCM)),
            .divider,
            .heading("Modules & Materials")
        ]
        for l in run.specLines { blocks.append(.row("\(l.name) — \(l.detail)", "×\(l.qty)")) }
        blocks.append(.spacer(8))
        if !run.notes.isEmpty { blocks.append(.heading("Notes")); blocks.append(.note(run.notes)) }
        return write(name: "CabFit-Order-" + FileExporter.safeName(run.title), blocks: blocks)
    }

    static func report(run: KitchenRun, decision: String,
                       includeLayout: Bool, includeSpec: Bool, includeCost: Bool) -> URL? {
        var blocks: [Block] = [
            .title("Cab Fit — Kitchen Report"),
            .row("Run", run.title),
            .row("Status", run.status.title),
            .row("Decision", decision),
            .row("Reviewer", run.reviewer.isEmpty ? "—" : run.reviewer),
            .divider
        ]
        if includeLayout {
            blocks.append(.heading("Layout"))
            blocks.append(.row("Base units", "\(run.baseUnitCount)"))
            blocks.append(.row("Wall units", "\(run.wallUnitCount)"))
            blocks.append(.row("Appliance slots", "\(run.appliances.count)"))
            blocks.append(.row("Leftover", String(format: "%.1f cm", run.leftoverCM)))
            blocks.append(.row("Fit", "\(Int(run.fitFraction * 100))%"))
            let t = run.triangle.rating
            blocks.append(.row("Work triangle", "\(t.title) (\(String(format: "%.0f cm", run.triangle.sum)))"))
            blocks.append(.divider)
        }
        if includeSpec {
            blocks.append(.heading("Spec & Materials"))
            for l in run.specLines { blocks.append(.row("\(l.name) — \(l.detail)", "×\(l.qty)")) }
            blocks.append(.divider)
        }
        if includeCost {
            blocks.append(.heading("Cost Estimate"))
            blocks.append(.row("Cabinets", run.currency + String(format: "%.0f", run.cabinetsCost())))
            blocks.append(.row("Fronts", run.currency + String(format: "%.0f", run.frontsCost())))
            blocks.append(.row("Worktop", run.currency + String(format: "%.0f", run.worktopCost())))
            blocks.append(.row("Reserve", run.currency + String(format: "%.0f", run.reserveAmount())))
            blocks.append(.row("TOTAL", run.currency + String(format: "%.0f", run.totalCost())))
        }
        if !run.defects.isEmpty {
            blocks.append(.divider)
            blocks.append(.heading("Defects & Fit Notes"))
            for d in run.defects { blocks.append(.row("\(d.issueType) (\(d.severity.title))", d.fixAction.isEmpty ? "—" : d.fixAction)) }
        }
        let issues = run.issues
        if !issues.isEmpty {
            blocks.append(.divider)
            blocks.append(.heading("Checks"))
            for i in issues { blocks.append(.row("\(i.title) — \(i.detail)", i.level.title)) }
        }
        if !run.markups.isEmpty {
            blocks.append(.divider)
            blocks.append(.heading("Service Markups"))
            for (n, m) in run.markups.enumerated() {
                blocks.append(.row("\(n + 1). \(m.kind)" + (m.caption.isEmpty ? "" : " — \(m.caption)"),
                                   m.severity.title))
            }
        }
        if includeLayout, let photo = run.photo {
            blocks.append(.divider)
            blocks.append(.heading("Wall Photo"))
            blocks.append(.image(photo, maxHeight: 240))
        }
        if let sig = run.signature {
            blocks.append(.divider)
            blocks.append(.heading("Signature"))
            blocks.append(.image(sig, maxHeight: 90))
            blocks.append(.note(run.reviewer.isEmpty ? "Signed" : "Signed by \(run.reviewer)"))
        }
        return write(name: "CabFit-Report-" + FileExporter.safeName(run.title), blocks: blocks)
    }

    private static func write(name: String, blocks: [Block]) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".pdf")
        let titleColor = UIColor(hexString: "102A4A")
        let blueColor = UIColor(hexString: "1F6FE0")
        let textColor = UIColor(hexString: "14315C")
        let mute = UIColor(hexString: "44587A")

        func measure(_ s: String, font: UIFont, width: CGFloat) -> CGFloat {
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
            let attr: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
            return ceil((s as NSString).boundingRect(with: CGSize(width: width, height: 10_000),
                                                     options: [.usesLineFragmentOrigin],
                                                     attributes: attr, context: nil).height)
        }

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y = margin

                func draw(_ s: String, font: UIFont, color: UIColor,
                          x: CGFloat = margin, width: CGFloat = pageRect.width - margin * 2,
                          alignment: NSTextAlignment = .left, at yPos: CGFloat) -> CGFloat {
                    let para = NSMutableParagraphStyle()
                    para.lineBreakMode = .byWordWrapping
                    para.alignment = alignment
                    let attr: [NSAttributedString.Key: Any] =
                        [.font: font, .foregroundColor: color, .paragraphStyle: para]
                    let h = measure(s, font: font, width: width)
                    (s as NSString).draw(with: CGRect(x: x, y: yPos, width: width, height: h),
                                         options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                    return h
                }

                /// Start a new page if `h` would run past the bottom margin. Heights are
                /// measured from the real text, so a long line no longer spills off the
                /// page or overlaps the row beneath it.
                func ensure(_ h: CGFloat) {
                    if y + h > pageRect.height - margin - 24 { ctx.beginPage(); y = margin }
                }

                let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
                let rightFont = UIFont.systemFont(ofSize: 12, weight: .bold)
                let rWidth: CGFloat = 120
                let leftWidth = pageRect.width - margin * 2 - rWidth - 8

                for block in blocks {
                    switch block {
                    case .title(let t):
                        let f = UIFont.systemFont(ofSize: 22, weight: .heavy)
                        let h = measure(t, font: f, width: pageRect.width - margin * 2)
                        ensure(h + 8)
                        y += draw(t, font: f, color: titleColor, at: y) + 8

                    case .heading(let t):
                        let f = UIFont.systemFont(ofSize: 15, weight: .bold)
                        let h = measure(t, font: f, width: pageRect.width - margin * 2)
                        ensure(h + 6)
                        y += draw(t, font: f, color: blueColor, at: y) + 6

                    case .row(let l, let r):
                        let lh = measure(l, font: bodyFont, width: leftWidth)
                        let rh = measure(r, font: rightFont, width: rWidth)
                        let h = max(lh, rh, 16)
                        ensure(h + 4)
                        _ = draw(l, font: bodyFont, color: textColor, x: margin, width: leftWidth, at: y)
                        _ = draw(r, font: rightFont, color: titleColor,
                                 x: pageRect.width - margin - rWidth, width: rWidth,
                                 alignment: .right, at: y)
                        y += h + 4

                    case .note(let t):
                        let h = measure(t, font: bodyFont, width: pageRect.width - margin * 2)
                        ensure(h + 4)
                        y += draw(t, font: bodyFont, color: mute, at: y) + 4

                    case .spacer(let h):
                        y += h

                    case .divider:
                        ensure(12)
                        let p = UIBezierPath()
                        p.move(to: CGPoint(x: margin, y: y))
                        p.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
                        UIColor(hexString: "C9DCEF").setStroke(); p.lineWidth = 1; p.stroke()
                        y += 12

                    case .image(let data, let maxHeight):
                        guard let img = UIImage(data: data) else { break }
                        let w = pageRect.width - margin * 2
                        let scale = min(w / max(img.size.width, 1), maxHeight / max(img.size.height, 1))
                        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                        ensure(size.height + 8)
                        img.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
                        y += size.height + 8
                    }
                }

                // Footer on the final page.
                let footer = "Generated by Cab Fit • local, private"
                let fAttr: [NSAttributedString.Key: Any] =
                    [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: mute]
                (footer as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - 28),
                                          withAttributes: fAttr)
            }
            return url
        } catch { return nil }
    }
}

// MARK: - Plain-file exporter

/// Writes text exports (CSV, JSON) into the temp directory for the share sheet.
enum FileExporter {
    static func safeName(_ s: String) -> String {
        let cleaned = String(s.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        })
        return cleaned.isEmpty ? "Run" : String(cleaned.prefix(40))
    }

    static func csv(_ text: String, name: String) -> URL? {
        write(text, name: name, ext: "csv")
    }

    static func write(_ text: String, name: String, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).\(ext)")
        // A BOM keeps Excel from mangling °, £ and other non-ASCII on open.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        do { try data.write(to: url); return url } catch { return nil }
    }
}

