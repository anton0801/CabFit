//
//  EngineViews.swift
//  CabFit
//
//  The layout / ergonomics engine screens (03–12). Every control mutates the run
//  binding and persists automatically through the DataStore.
//

import SwiftUI

func cfFlash(_ toast: Binding<String?>, _ text: String) {
    withAnimation { toast.wrappedValue = text }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
        withAnimation { toast.wrappedValue = nil }
    }
}

struct EngineNavLink<Destination: View>: View {
    let title: String
    let icon: String
    let destination: Destination
    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
            }
            .font(.cfHead(15)).foregroundColor(CF.blue)
            .padding(.vertical, 14).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13).fill(CF.blue.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(CF.blue.opacity(0.25), lineWidth: 1))
        }.buttonStyle(PlainButtonStyle())
    }
}

private func miniLabel(_ s: String) -> some View {
    HStack { Text(s.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundColor(CF.textMute); Spacer() }
}

/// Icon-only control with a full 44pt hit area and a spoken label. The list rows are
/// dense, so drawn size and touch size deliberately differ.
func iconButton(_ icon: String, _ tint: Color, _ label: String,
                size: CGFloat = 20, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }
    .buttonStyle(PlainButtonStyle())
    .accessibility(label: Text(label))
}

// MARK: - 03 Cabinet Run Builder 🔥

struct RunBuilderView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var snap = true
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Cabinet Run Builder",
                       subtitle: "Fit standard units along the wall.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 12) {
                    WallStripView(run: run, height: 70)
                    HStack(spacing: 10) {
                        MetricBadge(value: "\(run.baseUnitCount)", label: "Units placed", hex: "1F6FE0")
                        MetricBadge(value: settings.lenValue(max(0, run.leftoverCM)),
                                    label: "Leftover", hex: run.leftoverStatusHex)
                        MetricBadge(value: "\(Int(run.fitFraction * 100))%", label: "Filled", hex: "2FA85A")
                    }
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "square.grid.3x2.fill", title: "Module Widths")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ModuleStandard.allCases) { s in
                                Button(action: { run.moduleStandard = s }) {
                                    OptionChip(title: s.title, selected: run.moduleStandard == s)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    Text("Available widths: " + run.moduleStandard.widths.map { String(format: "%.0f", $0) }.joined(separator: " · ") + " cm")
                        .font(.cfBody(12)).foregroundColor(CF.textSec)
                    Toggle(isOn: $snap) {
                        Text("Snap to tolerance (\(settings.lenValue(run.toleranceCM)) \(settings.units.short))")
                            .font(.cfBody(13)).foregroundColor(CF.text)
                    }.toggleStyle(SwitchToggleStyle(tint: CF.blue))
                }
            }

            HStack(spacing: 10) {
                Button(action: build) {
                    HStack { Image(systemName: "wand.and.stars"); Text("Build Run") }
                }.buttonStyle(ActionButtonStyle())
                Button(action: { cfFlash($toast, "Run kept") }) { Text("Keep") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button(action: { run.units.removeAll { $0.type != .wall }; run.fillers.removeAll(); cfFlash($toast, "Cleared") }) {
                Text("Clear Fields")
            }.buttonStyle(GhostButtonStyle())

            if !run.units.filter({ $0.type != .wall }).isEmpty {
                CFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(icon: "list.bullet", title: "Placed Units (\(run.baseUnitCount))")
                        ForEach(run.units.filter { $0.type != .wall }) { u in
                            unitRow(u)
                        }
                    }
                }
            }

            EngineNavLink(title: "Open Filler & Gaps", icon: "rectangle.split.3x1",
                          destination: FillerGapsView(run: $run))
        }
    }

    private func unitRow(_ u: CabinetUnit) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: u.function.symbol).foregroundColor(CF.blue).frame(width: 22)
                Text(u.function.title).font(.cfBody(13)).foregroundColor(CF.title).lineLimit(1)
                Spacer(minLength: 4)
                iconButton("minus.circle.fill", CF.blue, "Narrow \(u.function.title)") { changeWidth(u, -5) }
                Text(settings.lenValue(u.widthCM)).font(.cfNum(14)).foregroundColor(CF.title).frame(minWidth: 40)
                iconButton("plus.circle.fill", CF.orange, "Widen \(u.function.title)") { changeWidth(u, 5) }
            }
            HStack(spacing: 10) {
                // Order along the wall matters — a sink between two drawer banks is a
                // different kitchen from a sink at the end.
                iconButton("arrow.left.circle", CF.textSec, "Move \(u.function.title) left") {
                    settings.haptic(); run.moveUnit(u.id, by: -1)
                }
                .opacity(run.canMoveUnit(u.id, by: -1) ? 1 : 0.3)
                .disabled(!run.canMoveUnit(u.id, by: -1))
                iconButton("arrow.right.circle", CF.textSec, "Move \(u.function.title) right") {
                    settings.haptic(); run.moveUnit(u.id, by: 1)
                }
                .opacity(run.canMoveUnit(u.id, by: 1) ? 1 : 0.3)
                .disabled(!run.canMoveUnit(u.id, by: 1))
                Spacer()
                Menu {
                    ForEach(UnitFunction.allCases) { f in
                        Button(action: { setFunction(u, f) }) { Label(f.title, systemImage: f.symbol) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Change").font(.cfBody(12)).foregroundColor(CF.blue)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(CF.blue)
                    }
                    .frame(height: 34)
                }
                iconButton("trash", CF.danger, "Delete \(u.function.title)") {
                    settings.haptic(); run.units.removeAll { $0.id == u.id }
                }
            }
            Divider().background(CF.divider)
        }
    }

    private func setFunction(_ u: CabinetUnit, _ f: UnitFunction) {
        if let i = run.units.firstIndex(where: { $0.id == u.id }) { run.units[i].function = f }
    }

    private func changeWidth(_ u: CabinetUnit, _ d: Double) {
        if let i = run.units.firstIndex(where: { $0.id == u.id }) {
            run.units[i].widthCM = max(15, min(120, run.units[i].widthCM + d))
        }
    }

    private func build() {
        settings.haptic(.medium)
        // rebuildBaseRun subtracts appliances, the corner AND any fillers already placed,
        // so building twice can no longer push the run past the end of the wall.
        run.rebuildBaseRun(snapToTolerance: snap)
        cfFlash($toast, "Run built — \(run.baseUnitCount) units")
    }
}

// MARK: - 04 Module Picker

struct ModulePickerView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var type: UnitType = .base
    @State private var function: UnitFunction = .standard
    @State private var width: Double = 60
    @State private var depth: Double = 60
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Module Picker",
                       subtitle: "Pick base, wall and tall units.",
                       toast: $toast) {
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "square.stack.3d.up", title: "New Unit")
                    miniLabel("Unit Type")
                    HStack(spacing: 8) {
                        ForEach(UnitType.allCases) { t in
                            Button(action: { type = t; depth = t.defaultDepth }) {
                                OptionChip(title: t.title, systemImage: t.symbol, selected: type == t)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    miniLabel("Function")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(UnitFunction.allCases) { f in
                                Button(action: { function = f }) {
                                    OptionChip(title: f.title, systemImage: f.symbol, selected: function == f, accent: CF.orange)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        miniLabel("Width")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(run.moduleStandard.widths, id: \.self) { w in
                                    Button(action: { width = w }) {
                                        OptionChip(title: String(format: "%.0f", w), selected: abs(width - w) < 0.1)
                                    }.buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        CFStepperRow(label: "Width", value: $width, step: 5, range: 15...120)
                    }
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Depth", value: $depth, step: 1, range: 28...70)
                    Button(action: add) {
                        HStack { Image(systemName: "plus"); Text("Add Unit") }
                    }.buttonStyle(ActionButtonStyle())
                }
            }

            if run.units.isEmpty {
                CFCard { Text("No units yet — add base, wall or tall modules.")
                    .font(.cfBody(13)).foregroundColor(CF.textMute).frame(maxWidth: .infinity).padding(.vertical, 8) }
            } else {
                CFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(icon: "list.bullet", title: "Units (\(run.units.count))")
                        ForEach(run.units) { u in
                            HStack(spacing: 10) {
                                Image(systemName: u.function.symbol).foregroundColor(colorFor(u.type)).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.function.title).font(.cfBody(13)).foregroundColor(CF.title)
                                    Text("\(u.type.title) • \(settings.lenValue(u.widthCM))×\(settings.lenValue(u.depthCM)) \(settings.units.short)")
                                        .font(.cfBody(11)).foregroundColor(CF.textSec)
                                }
                                Spacer()
                                Button(action: { run.units.removeAll { $0.id == u.id } }) {
                                    Image(systemName: "trash").foregroundColor(CF.textMute) }
                            }
                        }
                    }
                }
            }

            EngineNavLink(title: "Open Filler & Gaps", icon: "rectangle.split.3x1",
                          destination: FillerGapsView(run: $run))
        }
    }

    private func colorFor(_ t: UnitType) -> Color { t == .wall ? CF.blueHi : (t == .tall ? CF.orange : CF.blue) }

    private func add() {
        settings.haptic()
        run.units.append(CabinetUnit(type: type, function: function, widthCM: width, depthCM: depth))
        cfFlash($toast, "Unit added")
    }
}

// MARK: - 05 Filler & Gaps 🔥

struct FillerGapsView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var count: Double = 2
    @State private var evenSplit = true
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Filler & Gaps",
                       subtitle: "Turn leftover space into even fillers.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 12) {
                    WallStripView(run: run, height: 64)
                    HStack(spacing: 10) {
                        MetricBadge(value: settings.lenValue(max(0, run.leftoverCM)),
                                    label: "Leftover", hex: run.leftoverStatusHex)
                        MetricBadge(value: "\(run.fillers.count)", label: "Strips", hex: "F6BE24")
                        MetricBadge(value: settings.lenValue(run.fillersTotalCM), label: "Filled", hex: "1F6FE0")
                    }
                    if run.leftoverCM < -0.5 {
                        warn("Run overflows the wall by \(settings.len(abs(run.leftoverCM))). Remove a unit or narrow widths.")
                    } else if run.leftoverCM > 12 {
                        warn("Big leftover (\(settings.len(run.leftoverCM))). Split it into even fillers, not one strip.")
                    }
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "rectangle.split.3x1", title: "Distribute Filler")
                    Toggle(isOn: $evenSplit) {
                        Text("Even split across ends / corner").font(.cfBody(13)).foregroundColor(CF.text)
                    }.toggleStyle(SwitchToggleStyle(tint: CF.blue))
                    if evenSplit {
                        CFStepperRow(label: "Filler strips", value: $count, step: 1, range: 1...6, kind: .raw("pcs"))
                    }
                    if recoverable > 0 {
                        Text(evenSplit
                             ? "\(Int(count)) strips of about \(settings.len(recoverable / count))"
                             : "One \(settings.len(recoverable)) strip at the \(run.cornerType == .none ? "end of the run" : "corner")")
                            .font(.cfBody(12)).foregroundColor(CF.blue)
                    } else {
                        Text("No spare wall to fill — the run is already flush.")
                            .font(.cfBody(12)).foregroundColor(CF.textMute)
                    }
                    Button(action: apply) {
                        HStack { Image(systemName: "checkmark"); Text("Apply Fillers") }
                    }.buttonStyle(ActionButtonStyle())
                }
            }

            if !run.fillers.isEmpty {
                CFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(icon: "list.bullet", title: "Fillers")
                        ForEach(run.fillers) { f in fillerRow(f) }
                    }
                }
            }

            EngineNavLink(title: "Open Appliance Slots", icon: "flame.fill",
                          destination: ApplianceSlotsView(run: $run))
        }
    }

    private func fillerRow(_ f: Filler) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(CF.yellow.opacity(0.2)).frame(width: 26, height: 26)
                DiagonalHatch(spacing: 4).stroke(CF.yellow, lineWidth: 1).frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Menu {
                ForEach(["Left wall", "Right wall", "Corner"], id: \.self) { p in
                    Button(action: { setPos(f, p) }) { Text(p) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(f.position).font(.cfBody(13)).foregroundColor(CF.title)
                    Image(systemName: "chevron.down").font(.system(size: 10)).foregroundColor(CF.textMute)
                }
            }
            Spacer()
            Button(action: { changeWidth(f, -1) }) { Image(systemName: "minus.circle.fill").foregroundColor(CF.blue) }
            Text(settings.lenValue(f.widthCM)).font(.cfNum(14)).foregroundColor(CF.title).frame(minWidth: 38)
            Button(action: { changeWidth(f, 1) }) { Image(systemName: "plus.circle.fill").foregroundColor(CF.orange) }
            Button(action: { run.fillers.removeAll { $0.id == f.id } }) { Image(systemName: "trash").foregroundColor(CF.textMute) }
        }
    }

    private func warn(_ s: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(CF.warn)
            Text(s).font(.cfBody(12)).foregroundColor(CF.text)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(CF.warn.opacity(0.12)))
    }

    private func setPos(_ f: Filler, _ p: String) {
        if let i = run.fillers.firstIndex(where: { $0.id == f.id }) { run.fillers[i].position = p }
    }
    private func changeWidth(_ f: Filler, _ d: Double) {
        if let i = run.fillers.firstIndex(where: { $0.id == f.id }) {
            run.fillers[i].widthCM = max(0.5, min(60, run.fillers[i].widthCM + d))
        }
    }
    /// Wall left over once the fillers already placed are handed back.
    private var recoverable: Double { max(0, run.leftoverCM + run.fillersTotalCM) }

    private func apply() {
        settings.haptic(.medium)
        guard recoverable > 0 else {
            run.fillers.removeAll()
            cfFlash($toast, "Nothing to fill")
            return
        }
        let strips = evenSplit ? Int(count) : 1
        run.fillers = KitchenRun.evenFillers(leftover: recoverable, count: strips,
                                             corner: run.cornerType != .none)
        cfFlash($toast, strips == 1 ? "Single filler applied" : "\(strips) fillers applied")
    }
}

// MARK: - 06 Appliance Slots 🔥

struct ApplianceSlotsView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var kind: ApplianceKind = .fridge
    @State private var width: Double = 60
    @State private var clearance: Double = 2
    @State private var water = false
    @State private var power = true
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Appliance Slots",
                       subtitle: "Reserve appliance slots with clearances.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 12) {
                    WallStripView(run: run, height: 64)
                    HStack(spacing: 10) {
                        MetricBadge(value: "\(run.appliances.count)", label: "Slots", hex: "F77A1E")
                        MetricBadge(value: settings.lenValue(run.applianceTotalCM), label: "Reserved", hex: "F77A1E")
                        MetricBadge(value: settings.lenValue(max(0, run.leftoverCM)), label: "Leftover", hex: run.leftoverStatusHex)
                    }
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "flame.fill", title: "New Slot")
                    miniLabel("Appliance")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ApplianceKind.allCases) { k in
                                Button(action: { selectKind(k) }) {
                                    OptionChip(title: k.title, systemImage: k.symbol, selected: kind == k, accent: CF.orange)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    CFStepperRow(label: "Slot width", value: $width, step: 5, range: 30...120)
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Clearance / side", value: $clearance, step: 0.5, range: 0...10)
                    HStack(spacing: 10) {
                        Toggle(isOn: $water) { Text("Water").font(.cfBody(13)).foregroundColor(CF.text) }
                            .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                        Toggle(isOn: $power) { Text("Power").font(.cfBody(13)).foregroundColor(CF.text) }
                            .toggleStyle(SwitchToggleStyle(tint: CF.orange))
                    }
                    Text("Total wall space used: \(settings.len(width + clearance * 2))")
                        .font(.cfBody(12)).foregroundColor(CF.orange)
                    Button(action: add) {
                        HStack { Image(systemName: "plus"); Text("Add Slot") }
                    }.buttonStyle(ActionButtonStyle())
                }
            }

            if !run.appliances.isEmpty {
                CFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(icon: "list.bullet", title: "Reserved Slots")
                        ForEach(run.appliances) { a in slotRow(a) }
                    }
                }
            }

            EngineNavLink(title: "Open Work Triangle", icon: "triangle.fill",
                          destination: WorkTriangleView(run: $run))
        }
    }

    private func slotRow(_ a: ApplianceSlot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack { RoundedRectangle(cornerRadius: 8).stroke(CF.orange, lineWidth: 2).frame(width: 34, height: 34)
                    Image(systemName: a.kind.symbol).foregroundColor(CF.orange) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.kind.title).font(.cfHead(13)).foregroundColor(CF.title)
                    HStack(spacing: 6) {
                        Text("\(settings.lenValue(a.slotWidthCM)) + \(settings.lenValue(a.clearanceCM))×2")
                            .font(.cfBody(11)).foregroundColor(CF.textSec)
                        if a.hasWater { Image(systemName: "drop.fill").font(.system(size: 10)).foregroundColor(CF.blue) }
                        if a.hasPower { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundColor(CF.orange) }
                    }
                }
                Spacer()
                Text(settings.lenValue(a.totalWidthCM)).font(.cfNum(14)).foregroundColor(CF.orange)
            }
            // Correcting a measured slot used to mean deleting it and starting again.
            HStack(spacing: 6) {
                iconButton("minus.circle.fill", CF.blue, "Narrow \(a.kind.title) slot", size: 18) {
                    changeSlot(a, width: -5)
                }
                Text("slot").font(.cfBody(11)).foregroundColor(CF.textMute)
                iconButton("plus.circle.fill", CF.orange, "Widen \(a.kind.title) slot", size: 18) {
                    changeSlot(a, width: 5)
                }
                Divider().frame(height: 18).background(CF.divider)
                iconButton("minus.circle", CF.blue, "Less clearance for \(a.kind.title)", size: 18) {
                    changeSlot(a, clearance: -0.5)
                }
                Text("clear").font(.cfBody(11)).foregroundColor(CF.textMute)
                iconButton("plus.circle", CF.orange, "More clearance for \(a.kind.title)", size: 18) {
                    changeSlot(a, clearance: 0.5)
                }
                Spacer()
                iconButton(a.hasWater ? "drop.fill" : "drop", a.hasWater ? CF.blue : CF.textMute,
                           "Toggle water for \(a.kind.title)", size: 16) { toggleWater(a) }
                iconButton(a.hasPower ? "bolt.fill" : "bolt", a.hasPower ? CF.orange : CF.textMute,
                           "Toggle power for \(a.kind.title)", size: 16) { togglePower(a) }
                iconButton("trash", CF.danger, "Remove \(a.kind.title) slot", size: 16) {
                    settings.haptic(); run.appliances.removeAll { $0.id == a.id }
                }
            }
            Divider().background(CF.divider)
        }
    }

    private func changeSlot(_ a: ApplianceSlot, width: Double = 0, clearance: Double = 0) {
        guard let i = run.appliances.firstIndex(where: { $0.id == a.id }) else { return }
        settings.haptic()
        if width != 0 {
            run.appliances[i].slotWidthCM = min(120, max(30, run.appliances[i].slotWidthCM + width))
        }
        if clearance != 0 {
            run.appliances[i].clearanceCM = min(10, max(0, run.appliances[i].clearanceCM + clearance))
        }
    }
    private func toggleWater(_ a: ApplianceSlot) {
        guard let i = run.appliances.firstIndex(where: { $0.id == a.id }) else { return }
        settings.haptic(); run.appliances[i].hasWater.toggle()
    }
    private func togglePower(_ a: ApplianceSlot) {
        guard let i = run.appliances.firstIndex(where: { $0.id == a.id }) else { return }
        settings.haptic(); run.appliances[i].hasPower.toggle()
    }

    private func selectKind(_ k: ApplianceKind) {
        kind = k; width = k.defaultWidth; clearance = k.defaultClearance
        water = k.needsWater; power = k.needsPower
    }
    private func add() {
        settings.haptic()
        run.appliances.append(ApplianceSlot(kind: kind, slotWidthCM: width, clearanceCM: clearance,
                                            hasWater: water, hasPower: power))
        cfFlash($toast, "\(kind.title) slot added")
    }
}

// MARK: - 07 Work Triangle 🔥

struct WorkTriangleView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Work Triangle",
                       subtitle: "Check the sink–hob–fridge triangle.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 12) {
                    Text("Drag sink, hob and fridge to position them")
                        .font(.cfBody(12)).foregroundColor(CF.textMute)
                    TriangleCanvas(triangle: $run.triangle).frame(height: 240)
                    let t = run.scaledTriangle
                    let r = t.rating
                    HStack {
                        StatusPill(text: r.title, hex: r.hex)
                        Spacer()
                        Text("Sum " + settings.len(t.sum))
                            .font(.cfNum(16)).foregroundColor(Color(hex: r.hex))
                    }
                    Text(r.advice).font(.cfBody(12)).foregroundColor(CF.textSec)
                    Text("Plan \(settings.len(Double(run.planSizeCM.width))) × \(settings.len(Double(run.planSizeCM.height)))")
                        .font(.cfBody(11)).foregroundColor(CF.textMute)
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "triangle.fill", title: "Legs")
                    legRow("Sink → Hob", run.scaledTriangle.legSinkHob)
                    legRow("Hob → Fridge", run.scaledTriangle.legHobFridge)
                    legRow("Fridge → Sink", run.scaledTriangle.legFridgeSink)
                    Divider().background(CF.divider)
                    HStack {
                        Text("Triangle Sum").font(.cfHead(14)).foregroundColor(CF.title)
                        Spacer()
                        Text(settings.len(run.scaledTriangle.sum)).font(.cfNum(16)).foregroundColor(CF.orange)
                    }
                    Text("Comfortable kitchens keep each leg 120–270 cm and the sum 360–790 cm.")
                        .font(.cfBody(11)).foregroundColor(CF.textMute)
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(icon: "ruler.fill", title: "Plan Scale",
                                  subtitle: "The triangle is measured against this footprint")
                    // Without a room depth the third point is just a dot on a canvas —
                    // the legs are only real once the plan has a size.
                    CFStepperRow(label: "Room depth", value: $run.roomDepthCM, step: 10, range: 120...900)
                    Text("Width comes from wall A (\(settings.len(run.wallLengthCM)))" +
                         (run.shape == .lShape || run.shape == .uShape
                          ? "; depth from wall B when set." : "."))
                        .font(.cfBody(11)).foregroundColor(CF.textMute)
                }
            }

            HStack(spacing: 10) {
                Button(action: { cfFlash($toast, run.scaledTriangle.rating.title) }) {
                    HStack { Image(systemName: "gauge"); Text("Evaluate") }
                }.buttonStyle(ActionButtonStyle())
                Button(action: resetPoints) { Text("Reset") }.buttonStyle(SecondaryButtonStyle())
            }

            EngineNavLink(title: "Open Corner Solution", icon: "arrow.turn.up.right",
                          destination: CornerSolutionView(run: $run))
        }
    }

    private func legRow(_ name: String, _ cm: Double) -> some View {
        HStack {
            Text(name).font(.cfBody(13)).foregroundColor(CF.text)
            Spacer()
            Text(settings.len(cm)).font(.cfNum(14))
                .foregroundColor(cm < 120 || cm > 270 ? CF.warn : CF.ok)
        }
    }
    private func resetPoints() {
        settings.haptic()
        run.triangle.sink = CGPoint(x: 0.22, y: 0.30)
        run.triangle.hob = CGPoint(x: 0.74, y: 0.30)
        run.triangle.fridge = CGPoint(x: 0.50, y: 0.82)
        cfFlash($toast, "Triangle reset")
    }
}

struct TriangleCanvas: View {
    @Binding var triangle: WorkTriangle
    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(CF.bg2)
                RoundedRectangle(cornerRadius: 14).stroke(CF.border, lineWidth: 1)
                // triangle lines (orange)
                Path { p in
                    p.move(to: pt(triangle.sink, s)); p.addLine(to: pt(triangle.hob, s))
                    p.addLine(to: pt(triangle.fridge, s)); p.closeSubpath()
                }
                .stroke(CF.orange, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                Path { p in
                    p.move(to: pt(triangle.sink, s)); p.addLine(to: pt(triangle.hob, s))
                    p.addLine(to: pt(triangle.fridge, s)); p.closeSubpath()
                }
                .fill(CF.orange.opacity(0.08))

                node("Sink", "drop.fill", CF.blue, point: $triangle.sink, size: s)
                node("Hob", "flame.fill", CF.orange, point: $triangle.hob, size: s)
                node("Fridge", "snowflake", CF.blueAct, point: $triangle.fridge, size: s)
            }
        }
    }

    private func pt(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * s.width, y: CGFloat(p.y) * s.height)
    }

    private func node(_ title: String, _ icon: String, _ color: Color,
                      point: Binding<CGPoint>, size: CGSize) -> some View {
        let pos = pt(point.wrappedValue, size)
        return VStack(spacing: 2) {
            ZStack {
                Circle().fill(color).frame(width: 40, height: 40)
                    .shadow(color: color.opacity(0.5), radius: 6)
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            }
            Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(color)
        }
        .position(x: pos.x, y: pos.y)
        .gesture(DragGesture().onChanged { v in
            let nx = min(0.95, max(0.05, Double(v.location.x / size.width)))
            let ny = min(0.95, max(0.05, Double(v.location.y / size.height)))
            point.wrappedValue = CGPoint(x: nx, y: ny)
        })
    }
}

// MARK: - 08 Corner Solution 🔥

struct CornerSolutionView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Corner Solution",
                       subtitle: "Solve the corner without dead space.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 12) {
                    CornerDiagram(choice: run.cornerChoice).frame(height: 150)
                    Text(run.cornerChoice.deadSpaceNote).font(.cfBody(12)).foregroundColor(CF.textSec)
                        .multilineTextAlignment(.center)
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "arrow.turn.up.right", title: "Corner Setup")
                    miniLabel("Corner Type")
                    HStack(spacing: 8) {
                        ForEach(CornerType.allCases) { c in
                            Button(action: { run.cornerType = c }) {
                                OptionChip(title: c.title, selected: run.cornerType == c)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    miniLabel("Unit Choice")
                    VStack(spacing: 8) {
                        ForEach(CornerUnitChoice.allCases.filter { $0 != .none }) { ch in
                            Button(action: { run.cornerChoice = ch }) {
                                HStack {
                                    Image(systemName: run.cornerChoice == ch ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(run.cornerChoice == ch ? CF.orange : CF.textMute)
                                    Text(ch.title).font(.cfBody(14)).foregroundColor(CF.title)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    if run.cornerChoice == .blindFiller {
                        Divider().background(CF.divider)
                        CFStepperRow(label: "Blind filler", value: $run.cornerBlindFillerCM, step: 1, range: 2...15)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: { settings.haptic(.medium); cfFlash($toast, "Corner set") }) {
                    HStack { Image(systemName: "checkmark"); Text("Set Corner") }
                }.buttonStyle(ActionButtonStyle())
                Button(action: { run.cornerChoice = .none; cfFlash($toast, "Cleared") }) { Text("Clear") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            EngineNavLink(title: "Open Wall Unit Align", icon: "square.split.2x1",
                          destination: WallUnitAlignView(run: $run))
        }
    }
}

struct CornerDiagram: View {
    let choice: CornerUnitChoice
    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                // L corner walls
                Path { p in
                    p.move(to: CGPoint(x: 20, y: 20)); p.addLine(to: CGPoint(x: 20, y: s.height - 20))
                    p.addLine(to: CGPoint(x: s.width - 20, y: s.height - 20))
                }.stroke(CF.blue, lineWidth: 3)

                // base run blocks along both walls
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4).fill(CF.blue.opacity(0.85))
                        .frame(width: 36, height: 26)
                        .position(x: 64 + CGFloat(i) * 42, y: s.height - 34)
                }
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4).fill(CF.blue.opacity(0.85))
                        .frame(width: 26, height: 34)
                        .position(x: 34, y: CGFloat(60 + i * 40))
                }

                // corner element
                switch choice {
                case .carousel:
                    ZStack { Circle().stroke(CF.orange, lineWidth: 2.5).frame(width: 56, height: 56)
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(CF.orange) }
                        .position(x: 40, y: s.height - 40)
                case .lCorner:
                    RoundedRectangle(cornerRadius: 5).stroke(CF.orange, lineWidth: 2.5)
                        .frame(width: 52, height: 52).position(x: 42, y: s.height - 42)
                case .blindFiller:
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(CF.yellow.opacity(0.25)).frame(width: 16, height: 40)
                        DiagonalHatch(spacing: 4).stroke(CF.yellow, lineWidth: 1).frame(width: 16, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }.position(x: 56, y: s.height - 36)
                case .none:
                    Text("?").font(.cfTitle(28)).foregroundColor(CF.textMute).position(x: 40, y: s.height - 40)
                }
            }
        }
    }
}

// MARK: - 09 Wall Unit Align

struct WallUnitAlignView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Wall Unit Align",
                       subtitle: "Align wall units over the base run.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 10) {
                    WallElevationStack(run: run, overHood: run.hoodGap)
                        .frame(height: 180)
                    HStack(spacing: 10) {
                        MetricBadge(value: "\(run.wallUnitCount)", label: "Wall units", hex: "1F6FE0")
                        MetricBadge(value: settings.lenValue(run.wallUnitBottomCM), label: "Bottom h", hex: "F77A1E")
                        MetricBadge(value: run.wallUnitsAligned ? "Yes" : "No", label: "Aligned", hex: run.wallUnitsAligned ? "2FA85A" : "F6BE24")
                    }
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "square.split.2x1", title: "Wall Units")
                    HStack(spacing: 10) {
                        Button(action: addWallUnit) {
                            HStack { Image(systemName: "plus"); Text("Add Wall Unit") }
                        }.buttonStyle(GhostButtonStyle())
                        Button(action: matchBase) {
                            HStack { Image(systemName: "arrow.triangle.2.circlepath"); Text("Match Base") }
                        }.buttonStyle(GhostButtonStyle())
                    }
                    CFStepperRow(label: "Bottom height", value: $run.wallUnitBottomCM, step: 1, range: 120...170)
                    Toggle(isOn: $run.hoodGap) { Text("Leave gap over hood").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.orange))
                    Toggle(isOn: $run.wallUnitsAligned) { Text("Seams aligned with base").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                }
            }

            if run.wallUnitCount > 0 {
                CFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(icon: "list.bullet", title: "Wall Units (\(run.wallUnitCount))")
                        ForEach(run.units.filter { $0.type == .wall }) { u in
                            HStack {
                                Image(systemName: "square.split.2x1").foregroundColor(CF.blueHi)
                                Text(settings.len(u.widthCM)).font(.cfBody(13)).foregroundColor(CF.title)
                                Spacer()
                                Button(action: { run.units.removeAll { $0.id == u.id } }) {
                                    Image(systemName: "trash").foregroundColor(CF.textMute) }
                            }
                        }
                    }
                }
            }

            Button(action: { settings.haptic(.medium); run.wallUnitsAligned = true; cfFlash($toast, "Wall units aligned") }) {
                HStack { Image(systemName: "checkmark"); Text("Align Units") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Toe Kick & Service", icon: "bolt.fill",
                          destination: ToeKickServiceView(run: $run))
        }
    }

    private func addWallUnit() {
        settings.haptic()
        run.units.append(CabinetUnit(type: .wall, function: .standard, widthCM: 60, depthCM: 35))
    }

    private func matchBase() {
        settings.haptic()
        // Build the new row first, then assign once. Appending inside the loop wrote the
        // whole database back per unit, and nothing goes above a hob, a tall unit or a
        // fridge housing.
        let skipped: Set<UnitFunction> = [.sink, .cooktop, .oven, .fridge, .pantry]
        let mirrored = run.units
            .filter { $0.type == .base && !skipped.contains($0.function) }
            .map { CabinetUnit(type: .wall, function: .standard, widthCM: $0.widthCM, depthCM: 35) }

        var rebuilt = run.units.filter { $0.type != .wall }
        rebuilt.append(contentsOf: mirrored)
        run.units = rebuilt
        run.wallUnitsAligned = true
        cfFlash($toast, mirrored.isEmpty ? "No base units to match" : "Matched \(mirrored.count) seams")
    }
}

struct WallElevationStack: View {
    let run: KitchenRun
    let overHood: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // A true elevation: everything is scaled off the ceiling height, so the
            // plinth, worktop, splashback and wall-unit underside sit where they will
            // really sit. The old version used fixed pixel heights, which meant the
            // "Bottom height" control changed a number and nothing else.
            let ceiling = max(180, run.heightCM)
            let py = { (cm: Double) -> CGFloat in CGFloat(cm / ceiling) * h }
            let denom = max(run.totalWallCM, 1)
            let px = { (cm: Double) -> CGFloat in CGFloat(cm / denom) * w }

            let baseUnits = run.units.filter { $0.type != .wall }
            let wallUnits = run.units.filter { $0.type == .wall }
            let wallUnitHeight = max(30, min(90, ceiling - run.wallUnitBottomCM - 8))
            let hobX = hobCentreCM(baseUnits)

            ZStack(alignment: .bottomLeading) {
                // splashback
                Rectangle()
                    .fill(CF.blue.opacity(0.18))
                    .frame(width: px(min(run.totalWallCM, run.baseUnitsTotalCM + run.applianceTotalCM)),
                           height: py(run.splashbackHeightCM))
                    .offset(y: -py(run.baseHeightCM))

                // base carcasses sitting on the plinth
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(baseUnits) { u in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(gradient: Gradient(colors: [CF.blue, CF.blueAct]),
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: max(2, px(u.widthCM) - 2),
                                   height: max(4, py(run.baseHeightCM - run.plinthHeightCM)))
                            .overlay(unitGlyph(u))
                    }
                    Spacer(minLength: 0)
                }
                .offset(y: -py(run.plinthHeightCM))

                // plinth
                Rectangle().fill(CF.blueAct.opacity(0.6))
                    .frame(width: px(run.baseUnitsTotalCM), height: max(2, py(run.plinthHeightCM)))

                // worktop slab
                Rectangle().fill(CF.textSec)
                    .frame(width: px(min(run.totalWallCM, run.baseUnitsTotalCM + run.applianceTotalCM)),
                           height: max(3, py(4)))
                    .offset(y: -py(run.baseHeightCM))

                // wall units, hung at their real underside height
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(wallUnits) { u in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(CF.blueHi)
                            .frame(width: max(2, px(u.widthCM) - 2), height: max(4, py(wallUnitHeight)))
                    }
                    Spacer(minLength: 0)
                }
                .offset(y: -py(run.wallUnitBottomCM))

                // hood gap marker over the hob
                if overHood, let x = hobX {
                    VStack(spacing: 2) {
                        Image(systemName: "wind").font(.system(size: 12, weight: .bold))
                            .foregroundColor(CF.orange)
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .foregroundColor(CF.orange)
                            .frame(width: px(60), height: max(6, py(wallUnitHeight)))
                    }
                    .offset(x: px(x) - px(30), y: -py(run.wallUnitBottomCM))
                }

                // floor line
                Rectangle().fill(CF.blueAct).frame(height: 2)

                if wallUnits.isEmpty {
                    Text("No wall units").font(.cfBody(11)).foregroundColor(CF.textMute)
                        .offset(x: 6, y: -py(run.wallUnitBottomCM) - 14)
                }
            }
        }
    }

    /// Centre of the hob along the wall, so the hood gap lands over it.
    private func hobCentreCM(_ baseUnits: [CabinetUnit]) -> Double? {
        var x: Double = 0
        for u in baseUnits {
            if u.function == .cooktop { return x + u.widthCM / 2 }
            x += u.widthCM
        }
        // Fall back to a reserved hob slot if the run has no cooktop module.
        guard run.appliances.contains(where: { $0.kind == .hob }) else { return nil }
        var slotX = run.baseUnitsTotalCM
        for a in run.appliances {
            if a.kind == .hob { return slotX + a.totalWidthCM / 2 }
            slotX += a.totalWidthCM
        }
        return nil
    }

    @ViewBuilder
    private func unitGlyph(_ u: CabinetUnit) -> some View {
        if u.function != .standard {
            Image(systemName: u.function.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - 10 Toe Kick & Service

struct ToeKickServiceView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil

    var body: some View {
        EngineScaffold(title: "Toe Kick & Service",
                       subtitle: "Set the plinth and services behind units.",
                       toast: $toast) {
            CFCard {
                PlinthDiagram(plinth: run.plinthHeightCM, legs: run.legsAdjustable,
                              sockets: run.socketsBehind, plumbing: run.plumbingBehind)
                    .frame(height: 140)
            }
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "bolt.fill", title: "Plinth & Services")
                    CFStepperRow(label: "Plinth height", value: $run.plinthHeightCM, step: 1, range: 8...20)
                    Toggle(isOn: $run.legsAdjustable) { Text("Adjustable legs").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                    Toggle(isOn: $run.socketsBehind) { Text("Sockets behind units").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.orange))
                    Toggle(isOn: $run.plumbingBehind) { Text("Plumbing behind units").font(.cfBody(13)).foregroundColor(CF.text) }
                        .toggleStyle(SwitchToggleStyle(tint: CF.blue))
                    if run.socketsBehind || run.plumbingBehind {
                        Text("Mark these on the photo markup so the carcass cut-outs are right.")
                            .font(.cfBody(11)).foregroundColor(CF.textMute)
                    }
                }
            }
            Button(action: { settings.haptic(.medium); cfFlash($toast, "Services set") }) {
                HStack { Image(systemName: "checkmark"); Text("Set Services") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Door Swing", icon: "arrow.left.and.right",
                          destination: DoorSwingView(run: $run))
        }
    }
}

struct PlinthDiagram: View {
    let plinth: Double; let legs: Bool; let sockets: Bool; let plumbing: Bool
    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(CF.bg2)
                // cabinet body
                RoundedRectangle(cornerRadius: 5).fill(CF.blue.opacity(0.85))
                    .frame(width: s.width - 60, height: s.height - 50)
                    .position(x: s.width/2, y: (s.height - 50)/2 + 6)
                // plinth
                Rectangle().fill(CF.blueAct)
                    .frame(width: s.width - 60, height: CGFloat(plinth))
                    .position(x: s.width/2, y: s.height - 22 - CGFloat(plinth)/2)
                // legs
                if legs {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(CF.textSec).frame(width: 4, height: 12)
                            .position(x: s.width/2 - CGFloat(s.width-90)/2 + CGFloat(i) * CGFloat(s.width-90)/3,
                                      y: s.height - 16)
                    }
                }
                // services
                if sockets {
                    Image(systemName: "bolt.fill").foregroundColor(CF.orange)
                        .position(x: s.width - 50, y: s.height/2)
                }
                if plumbing {
                    Image(systemName: "drop.fill").foregroundColor(CF.blueHi)
                        .position(x: s.width - 50, y: s.height/2 + 24)
                }
                Rectangle().fill(CF.blueAct).frame(height: 3).position(x: s.width/2, y: s.height - 8)
            }
        }
    }
}

// MARK: - 11 Door Swing & Handles

struct DoorSwingView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil
    private let sides = ["Left", "Right", "Mixed"]
    private let handles = ["Bar Handle", "Knob", "Recessed", "Push-to-open"]

    private var conflict: Bool { run.swingClearanceCM < 6 && !run.appliances.isEmpty }

    var body: some View {
        EngineScaffold(title: "Door Swing & Handles",
                       subtitle: "Check door swing and handle clearance.",
                       toast: $toast) {
            CFCard {
                DoorSwingDiagram(side: run.doorSide, clearance: run.swingClearanceCM).frame(height: 140)
            }
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "arrow.left.and.right", title: "Doors")
                    miniLabel("Door Side")
                    HStack(spacing: 8) {
                        ForEach(sides, id: \.self) { s in
                            Button(action: { run.doorSide = s }) {
                                OptionChip(title: s, selected: run.doorSide == s)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    CFStepperRow(label: "Swing clearance", value: $run.swingClearanceCM, step: 1, range: 0...30)
                    miniLabel("Handle Type")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(handles, id: \.self) { h in
                                Button(action: { run.handleType = h }) {
                                    OptionChip(title: h, selected: run.handleType == h, accent: CF.orange)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: conflict ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(conflict ? CF.danger : CF.ok)
                        Text(conflict ? "Tight swing near an appliance — increase clearance." : "No door clashes detected.")
                            .font(.cfBody(12)).foregroundColor(CF.text)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill((conflict ? CF.danger : CF.ok).opacity(0.12)))
                }
            }
            Button(action: { settings.haptic(.medium); cfFlash($toast, "Doors set") }) {
                HStack { Image(systemName: "checkmark"); Text("Set Doors") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Worktop Link", icon: "rectangle.portrait",
                          destination: WorktopView(run: $run))
        }
    }
}

struct DoorSwingDiagram: View {
    let side: String; let clearance: Double
    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(CF.bg2)
                RoundedRectangle(cornerRadius: 5).stroke(CF.blue, lineWidth: 2)
                    .frame(width: s.width - 80, height: s.height - 50)
                // swing arc
                Path { p in
                    let cx: CGFloat = side == "Right" ? s.width - 40 : 40
                    let start: Angle = side == "Right" ? .degrees(180) : .degrees(0)
                    let end: Angle = side == "Right" ? .degrees(270) : .degrees(-90)
                    p.move(to: CGPoint(x: cx, y: 30))
                    p.addArc(center: CGPoint(x: cx, y: 30), radius: 60,
                             startAngle: start, endAngle: end, clockwise: side == "Right")
                }.stroke(CF.orange, style: StrokeStyle(lineWidth: 2, dash: [4,3]))
                Text(String(format: "%.0f cm clear", clearance))
                    .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(CF.orange)
                    .position(x: s.width/2, y: s.height - 18)
            }
        }
    }
}

// MARK: - 12 Worktop & Splashback

struct WorktopView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil
    private let materials = ["Laminate", "Solid wood", "Quartz", "Granite", "Compact"]

    var body: some View {
        EngineScaffold(title: "Worktop & Splashback Link",
                       subtitle: "Link the worktop and splashback to the run.",
                       toast: $toast) {
            CFCard {
                WorktopDiagram(depth: run.worktopDepthCM, overhang: run.worktopOverhangCM,
                               splash: run.splashbackHeightCM).frame(height: 140)
            }
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "rectangle.portrait", title: "Worktop")
                    CFStepperRow(label: "Worktop depth", value: $run.worktopDepthCM, step: 1, range: 40...90)
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Overhang", value: $run.worktopOverhangCM, step: 0.5, range: 0...8)
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Splashback height", value: $run.splashbackHeightCM, step: 1, range: 0...90)
                    miniLabel("Material")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(materials, id: \.self) { m in
                                Button(action: { run.worktopMaterial = m }) {
                                    OptionChip(title: m, selected: run.worktopMaterial == m)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    Text("Worktop run length ≈ \(settings.len(run.baseUnitsTotalCM + run.applianceTotalCM))")
                        .font(.cfBody(12)).foregroundColor(CF.blue)
                }
            }
            Button(action: { settings.haptic(.medium); cfFlash($toast, "Worktop set") }) {
                HStack { Image(systemName: "checkmark"); Text("Set Worktop") }
            }.buttonStyle(ActionButtonStyle())

            EngineNavLink(title: "Open Spec List", icon: "list.bullet",
                          destination: SpecListView(run: $run))
        }
    }
}

struct WorktopDiagram: View {
    let depth: Double; let overhang: Double; let splash: Double

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            // A section through the worktop, scaled to whatever space the card gives it
            // instead of turning centimetres straight into points (a 90 cm worktop used
            // to draw 216 pt wide and run off the edge).
            let spanCM = max(depth + overhang, 40) * 1.25
            let scale = max(0.2, (s.width - 70) / CGFloat(spanCM))
            let wallX: CGFloat = 40
            let topY = s.height / 2
            let slabW = max(4, CGFloat(depth) * scale)
            let overW = max(2, CGFloat(overhang) * scale)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(CF.bg2)

                // wall line
                Rectangle().fill(CF.blueAct).frame(width: 2, height: s.height - 24)
                    .offset(x: wallX - 12, y: 12)

                // splashback rising off the back of the worktop
                Rectangle().fill(CF.blue.opacity(0.45))
                    .frame(width: 10, height: max(2, CGFloat(splash) * scale))
                    .offset(x: wallX - 10, y: topY - CGFloat(splash) * scale)

                // worktop slab
                RoundedRectangle(cornerRadius: 2).fill(CF.textSec)
                    .frame(width: slabW, height: 12)
                    .offset(x: wallX, y: topY)

                // the overhang, called out in orange at the front edge
                RoundedRectangle(cornerRadius: 2).fill(CF.orange)
                    .frame(width: overW, height: 12)
                    .offset(x: wallX + slabW - overW, y: topY)

                // carcass under the slab, set back by the overhang
                RoundedRectangle(cornerRadius: 3).fill(CF.blue.opacity(0.8))
                    .frame(width: max(4, slabW - overW), height: max(6, s.height / 2 - 44))
                    .offset(x: wallX, y: topY + 12)
            }
            .overlay(
                Text("depth \(Int(depth)) • overhang \(Int(overhang)) • splashback \(Int(splash)) cm")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(CF.textSec)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.bottom, 6).padding(.horizontal, 8),
                alignment: .bottom
            )
        }
    }
}
