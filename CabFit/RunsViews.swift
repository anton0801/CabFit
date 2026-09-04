//
//  RunsViews.swift
//  CabFit
//
//  Runs tab (list + create), Wall Dimension Capture, Run Detail card,
//  Photo Markup and Defect notes.
//

import SwiftUI

// MARK: - Runs tab

/// How the list is ordered. Persisted so the list looks the same next launch.
enum RunSort: String, CaseIterable, Identifiable {
    case newest, oldest, title, status, readiness
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest:    return "Newest first"
        case .oldest:    return "Oldest first"
        case .title:     return "Title A–Z"
        case .status:    return "By status"
        case .readiness: return "Least ready first"
        }
    }
    var symbol: String {
        switch self {
        case .newest, .oldest: return "calendar"
        case .title:           return "textformat"
        case .status:          return "flag.fill"
        case .readiness:       return "checklist"
        }
    }
}

struct RunsTab: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings

    @State private var showNew = false
    @State private var query = ""
    @State private var statusFilter: RunStatus? = nil
    @AppStorage("cf.runSort") private var sortRaw = RunSort.newest.rawValue
    @State private var pendingDelete: KitchenRun? = nil
    @State private var showUndo = false

    private var sort: RunSort { RunSort(rawValue: sortRaw) ?? .newest }

    /// Search matches the title, the shape and any defect text, so "door clash"
    /// finds the run that has one.
    private var visibleRuns: [KitchenRun] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = store.runs.filter { run in
            let statusOK = statusFilter == nil || run.status == statusFilter
            guard statusOK else { return false }
            guard !q.isEmpty else { return true }
            if run.title.lowercased().contains(q) { return true }
            if run.shape.title.lowercased().contains(q) { return true }
            if run.notes.lowercased().contains(q) { return true }
            if run.defects.contains(where: { $0.issueType.lowercased().contains(q) }) { return true }
            if run.appliances.contains(where: { $0.kind.title.lowercased().contains(q) }) { return true }
            return false
        }
        switch sort {
        case .newest:    list.sort { $0.dateCreated > $1.dateCreated }
        case .oldest:    list.sort { $0.dateCreated < $1.dateCreated }
        case .title:     list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .status:    list.sort { statusRank($0.status) < statusRank($1.status) }
        case .readiness: list.sort { $0.readiness < $1.readiness }
        }
        return list
    }

    private func statusRank(_ s: RunStatus) -> Int {
        switch s {
        case .planning: return 0
        case .inProgress: return 1
        case .ready: return 2
        case .approved: return 3
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                CF.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if store.loadFailed {
                            recoveryBanner
                        }
                        if store.runs.isEmpty {
                            emptyState
                        } else {
                            summaryStrip
                            searchAndFilter
                            if visibleRuns.isEmpty {
                                noMatchesState
                            } else {
                                ForEach(visibleRuns) { run in
                                    NavigationLink(destination: RunDetailView(runID: run.id)) {
                                        RunCard(run: run)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contextMenu {
                                        Button(action: { settings.haptic(); store.duplicate(run) }) {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }
                                        Button(action: { settings.haptic(); store.selectedRunID = run.id }) {
                                            Label("Set as active run", systemImage: "checkmark.circle")
                                        }
                                        Button(action: { pendingDelete = run }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        TabBottomSpacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }

                if showUndo, let pending = store.lastDeleted {
                    undoBar(title: pending.run.title)
                        .padding(.bottom, 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitle("Runs", displayMode: .inline)
            .navigationBarItems(
                leading: NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape.fill").foregroundColor(CF.blue)
                        .frame(width: 40, height: 40)
                }.accessibility(label: Text("Settings")),
                trailing: Button(action: { settings.haptic(); showNew = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22)).foregroundColor(CF.orange)
                        .frame(width: 40, height: 40)
                }.accessibility(label: Text("New run"))
            )
            // Deleting a run throws away photos, markups and a signature — always ask.
            .alert(item: $pendingDelete) { run in
                Alert(title: Text("Delete “\(run.title)”?"),
                      message: Text("The layout, photos and notes on this run go with it. You can undo straight after."),
                      primaryButton: .destructive(Text("Delete")) { performDelete(run) },
                      secondaryButton: .cancel())
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showNew) { NewRunSheet() }
    }

    private func performDelete(_ run: KitchenRun) {
        settings.haptic(.heavy)
        store.delete(run)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showUndo = true }
        // The undo window is deliberately short-lived; after it the delete is final.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            withAnimation { showUndo = false }
            store.clearUndo()
        }
    }

    private func undoBar(title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill").foregroundColor(.white)
            Text("Deleted “\(title)”").font(.cfBody(13)).foregroundColor(.white).lineLimit(1)
            Spacer(minLength: 6)
            Button(action: {
                settings.haptic()
                store.undoDelete()
                withAnimation { showUndo = false }
            }) {
                Text("Undo").font(.cfHead(14)).foregroundColor(CF.yellowHi)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(CF.title))
        .shadow(color: CF.shadow, radius: 10, y: 4)
        .padding(.horizontal, 20)
    }

    /// Shown when the stored database could not be read. The raw file is untouched,
    /// so the user can hand it to support instead of losing it.
    private var recoveryBanner: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "exclamationmark.triangle.fill",
                              title: "Saved runs couldn't be read",
                              subtitle: "Your old file is kept, not overwritten")
                Text("Open Settings → Data to export the raw backup, or start fresh from there.")
                    .font(.cfBody(13)).foregroundColor(CF.textSec)
            }
        }
    }

    private var searchAndFilter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(CF.textMute)
                TextField("Search runs, appliances, defects", text: $query)
                    .font(.cfBody(14)).foregroundColor(CF.title)
                    .disableAutocorrection(true)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(CF.textMute)
                            .frame(width: 32, height: 32)
                    }.accessibility(label: Text("Clear search"))
                }
                Menu {
                    ForEach(RunSort.allCases) { s in
                        Button(action: { sortRaw = s.rawValue }) {
                            if sort == s { Label(s.title, systemImage: "checkmark") }
                            else { Text(s.title) }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 20)).foregroundColor(CF.blue)
                        .frame(width: 36, height: 36)
                }.accessibility(label: Text("Sort order"))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(CF.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CF.border, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { statusFilter = nil }) {
                        OptionChip(title: "All \(store.runs.count)", selected: statusFilter == nil)
                    }.buttonStyle(PlainButtonStyle())
                    ForEach(RunStatus.allCases) { st in
                        let n = store.runs.filter { $0.status == st }.count
                        if n > 0 {
                            Button(action: { statusFilter = statusFilter == st ? nil : st }) {
                                OptionChip(title: "\(st.title) \(n)", selected: statusFilter == st,
                                           accent: Color(hex: st.hex))
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var noMatchesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 34)).foregroundColor(CF.textMute)
            Text("No runs match").font(.cfHead(16)).foregroundColor(CF.title)
            Text("Try a different search or clear the status filter.")
                .font(.cfBody(13)).foregroundColor(CF.textSec)
            Button(action: { query = ""; statusFilter = nil }) { Text("Clear filters") }
                .buttonStyle(GhostButtonStyle())
                .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            MetricBadge(value: "\(store.runs.count)", label: "Runs", hex: "1F6FE0")
            MetricBadge(value: "\(store.runs.reduce(0) { $0 + $1.baseUnitCount })",
                        label: "Units", hex: "F77A1E")
            MetricBadge(value: "\(store.runs.filter { $0.approved }.count)",
                        label: "Approved", hex: "2FA85A")
            MetricBadge(value: "\(store.runs.reduce(0) { $0 + $1.blockerCount })",
                        label: "Blockers",
                        hex: store.runs.contains(where: { $0.blockerCount > 0 }) ? "EF4444" : "2FA85A")
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(CF.blue.opacity(0.12)).frame(width: 110, height: 110)
                TowerAccent(index: 15, size: 96)
            }
            Text("No kitchen runs yet").font(.cfHead(20)).foregroundColor(CF.title)
            Text("Capture a wall, fit standard modules, reserve appliance slots and build the order sheet.")
                .font(.cfBody(14)).foregroundColor(CF.textSec)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button(action: { showNew = true }) {
                HStack { Image(systemName: "plus"); Text("Create Run") }
            }
            .buttonStyle(ActionButtonStyle())
            .padding(.horizontal, 40)
        }
        .padding(.top, 70)
    }
}

// MARK: - Run card

struct RunCard: View {
    @EnvironmentObject var settings: AppSettings
    let run: KitchenRun

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.title).font(.cfHead(18)).foregroundColor(CF.title).lineLimit(1)
                        Text(run.shape.title + " • " + run.moduleStandard.title)
                            .font(.cfBody(12)).foregroundColor(CF.textSec)
                        Text(RunCard.dateFormatter.string(from: run.dateCreated))
                            .font(.cfBody(11)).foregroundColor(CF.textMute)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        StatusPill(text: run.status.title, hex: run.status.hex)
                        ReadinessRing(progress: run.readiness, size: 30)
                    }
                }

                WallStripView(run: run, height: 58)

                // Fit health bar — turns red once the run is longer than the wall.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CF.bg2).frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: run.overflows
                                                   ? [CF.danger, CF.orange]
                                                   : [CF.blue, CF.blueHi]),
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * CGFloat(run.fitFraction)), height: 8)
                    }
                }.frame(height: 8)

                HStack(spacing: 16) {
                    miniMetric("\(run.baseUnitCount)", "modules", "square.grid.3x2.fill")
                    miniMetric("\(run.appliances.count)", "slots", "flame.fill")
                    miniMetric(run.overflows ? "-" + settings.lenValue(run.overflowCM)
                                             : settings.lenValue(run.leftoverCM),
                               run.overflows ? "over" : "leftover", "arrow.left.and.right")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(CF.textMute)
                }

                if run.blockerCount > 0 || run.warningCount > 0 {
                    HStack(spacing: 8) {
                        if run.blockerCount > 0 {
                            issueChip("\(run.blockerCount) blocker\(run.blockerCount == 1 ? "" : "s")",
                                      "xmark.octagon.fill", CF.danger)
                        }
                        if run.warningCount > 0 {
                            issueChip("\(run.warningCount) to check", "exclamationmark.triangle.fill", CF.warn)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func issueChip(_ text: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func miniMetric(_ v: String, _ l: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(CF.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(v).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(CF.title)
                Text(l).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundColor(CF.textMute)
            }
        }
    }
}

/// Small progress ring for the run readiness checklist.
struct ReadinessRing: View {
    let progress: Double
    var size: CGFloat = 34

    private var tint: Color {
        if progress >= 0.999 { return CF.ok }
        if progress >= 0.6 { return CF.blue }
        return CF.warn
    }

    var body: some View {
        ZStack {
            Circle().stroke(CF.bg2, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))")
                .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
        }
        .frame(width: size, height: size)
        .accessibility(label: Text("Readiness \(Int((progress * 100).rounded())) percent"))
    }
}

// MARK: - New run sheet (Wall Dimension Capture, create mode)

struct NewRunSheet: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.presentationMode) var presentation

    @State private var draft = KitchenRun()

    var body: some View {
        NavigationView {
            ZStack {
                CF.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        WallDrawing(run: draft).frame(height: 150)
                        WallFieldsCard(run: $draft)
                        Button(action: create) {
                            HStack { Image(systemName: "checkmark"); Text("Create Run Record") }
                        }.buttonStyle(ActionButtonStyle())
                    }
                    .padding(20)
                }
            }
            .navigationBarTitle("Wall Capture", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cancel") { presentation.wrappedValue.dismiss() }
                .foregroundColor(CF.blue))
            .onAppear {
                draft.moduleStandard = settings.defaultStandard
                draft.baseHeightCM = settings.defaultBaseHeight
                draft.currency = settings.currency
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func create() {
        settings.haptic(.medium)
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = "New Run" }
        store.addRun(draft)
        presentation.wrappedValue.dismiss()
    }
}

/// Shared editable wall fields (used by create + edit).
struct WallFieldsCard: View {
    @Binding var run: KitchenRun
    var body: some View {
        CFCard {
            VStack(spacing: 14) {
                CFTextField(label: "Project / Run", text: $run.title, placeholder: "Kitchen Wall A")

                fieldLabel("Kitchen Shape")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(KitchenShape.allCases) { s in
                            Button(action: { run.shape = s }) {
                                OptionChip(title: s.title, systemImage: s.symbol, selected: run.shape == s)
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                CFStepperRow(label: "Wall A length", value: $run.wallLengthCM, step: 5, range: 60...900)
                if run.shape != .singleWall {
                    Divider().background(CF.divider)
                    CFStepperRow(label: "Wall B length", value: $run.wallBLengthCM, step: 5, range: 0...900)
                }
                Divider().background(CF.divider)
                CFStepperRow(label: "Ceiling height", value: $run.heightCM, step: 5, range: 200...340)
                Divider().background(CF.divider)
                CFStepperRow(label: "Room depth", value: $run.roomDepthCM, step: 10, range: 120...900)
                Divider().background(CF.divider)
                CFStepperRow(label: "Tolerance", value: $run.toleranceCM, step: 0.5, range: 0...10)

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Corner Type")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CornerType.allCases) { c in
                                Button(action: { run.cornerType = c }) {
                                    OptionChip(title: c.title, selected: run.cornerType == c)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }
    private func fieldLabel(_ s: String) -> some View {
        HStack { Text(s.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(CF.textMute)
            Spacer() }
    }
}

/// A drafting-style wall elevation with dimension lines.
struct WallDrawing: View {
    @EnvironmentObject var settings: AppSettings
    let run: KitchenRun
    var body: some View {
        CFCard(padding: 14) {
            VStack(spacing: 8) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .bottom) {
                        // wall outline
                        RoundedRectangle(cornerRadius: 6).stroke(CF.blue, lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 6).fill(CF.blue.opacity(0.04)))
                        // height dimension (left)
                        Path { p in
                            p.move(to: CGPoint(x: 8, y: 6)); p.addLine(to: CGPoint(x: 8, y: geo.size.height - 6))
                        }.stroke(CF.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3,3]))
                        // length dimension (bottom)
                        Path { p in
                            p.move(to: CGPoint(x: 8, y: geo.size.height - 8))
                            p.addLine(to: CGPoint(x: w - 8, y: geo.size.height - 8))
                        }.stroke(CF.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3,3]))
                        Text(settings.len(run.wallLengthCM))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(CF.orange)
                            .padding(4).background(CF.card.opacity(0.9)).cornerRadius(5)
                            .padding(.bottom, 2)
                    }
                }
                .frame(height: 110)
                Text("Wall elevation • \(run.shape.title)")
                    .font(.cfBody(11)).foregroundColor(CF.textMute)
            }
        }
    }
}

// MARK: - Run detail

struct RunDetailView: View {
    @EnvironmentObject var store: DataStore
    let runID: UUID
    var body: some View {
        if let binding = store.binding(for: runID) {
            RunDetailContent(run: binding)
        } else {
            ZStack { CF.bg.ignoresSafeArea()
                Text("Run not found").foregroundColor(CF.textSec) }
        }
    }
}

struct RunDetailContent: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.presentationMode) var presentation
    @Binding var run: KitchenRun
    @State private var toast: String? = nil
    @State private var confirmDelete = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CF.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    readinessCard
                    if !run.issues.isEmpty { issuesCard }
                    sectionTitle("Layout & Engine")
                    engineLinks
                    sectionTitle("Capture & Issues")
                    captureLinks
                    sectionTitle("Output")
                    outputLinks
                    actions
                    TabBottomSpacer()
                }
                .padding(.horizontal, 20).padding(.top, 6)
            }
            if let t = toast { ConfirmToast(text: t).padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .navigationBarTitle("Run Detail", displayMode: .inline)
        .alert(isPresented: $confirmDelete) {
            Alert(title: Text("Delete “\(run.title)”?"),
                  message: Text("The layout, photos, defect notes and signature go with it."),
                  primaryButton: .destructive(Text("Delete")) {
                      settings.haptic(.heavy)
                      let doomed = run
                      presentation.wrappedValue.dismiss()
                      // Dismiss first: deleting while this screen is still bound to the
                      // run leaves the detail view reading a run that no longer exists.
                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                          store.delete(doomed)
                      }
                  },
                  secondaryButton: .cancel())
        }
    }

    private var headerCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                if let data = run.photo, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(height: 130).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                }
                TextField("Run title", text: $run.title)
                    .font(.cfHead(20)).foregroundColor(CF.title)

                HStack(spacing: 8) {
                    Menu {
                        ForEach(RunStatus.allCases) { s in
                            Button(action: { run.status = s }) { Text(s.title) }
                        }
                    } label: { StatusPill(text: run.status.title, hex: run.status.hex) }
                    Menu {
                        ForEach(Priority.allCases) { p in
                            Button(action: { run.priority = p }) { Text(p.title) }
                        }
                    } label: { StatusPill(text: run.priority.title + " priority", hex: run.priority.hex) }
                    Spacer()
                }

                WallStripView(run: run, height: 60)

                HStack(spacing: 10) {
                    MetricBadge(value: "\(run.baseUnitCount)", label: "Modules", hex: "1F6FE0")
                    MetricBadge(value: "\(run.appliances.count)", label: "Appliances", hex: "F77A1E")
                    MetricBadge(value: run.overflows ? "-" + settings.lenValue(run.overflowCM)
                                                     : settings.lenValue(run.leftoverCM),
                                label: run.overflows ? "Over" : "Leftover", hex: run.leftoverStatusHex)
                    MetricBadge(value: "\(Int(run.fitFraction * 100))%", label: "Filled", hex: "2FA85A")
                }
            }
        }
    }

    private var engineLinks: some View {
        VStack(spacing: 10) {
            navRow("Cabinet Run Builder", "Fit standard units along the wall", "square.grid.3x2.fill", CF.orange, hot: true,
                   dest: AnyView(RunBuilderView(run: $run)))
            navRow("Module Picker", "Pick base, wall and tall units", "square.stack.3d.up", CF.blue,
                   dest: AnyView(ModulePickerView(run: $run)))
            navRow("Filler & Gaps", "Turn leftover space into even fillers", "rectangle.split.3x1", CF.orange, hot: true,
                   dest: AnyView(FillerGapsView(run: $run)))
            navRow("Appliance Slots", "Reserve appliance slots with clearances", "flame.fill", CF.orange, hot: true,
                   dest: AnyView(ApplianceSlotsView(run: $run)))
            navRow("Work Triangle", "Check the sink–hob–fridge triangle", "triangle.fill", CF.orange, hot: true,
                   dest: AnyView(WorkTriangleView(run: $run)))
            navRow("Corner Solution", "Solve the corner without dead space", "arrow.turn.up.right", CF.orange, hot: true,
                   dest: AnyView(CornerSolutionView(run: $run)))
            navRow("Wall Unit Align", "Align wall units over the base run", "square.split.2x1", CF.blue,
                   dest: AnyView(WallUnitAlignView(run: $run)))
            navRow("Toe Kick & Service", "Set the plinth and services behind units", "bolt.fill", CF.blue,
                   dest: AnyView(ToeKickServiceView(run: $run)))
            navRow("Door Swing & Handles", "Check door swing and handle clearance", "arrow.left.and.right", CF.blue,
                   dest: AnyView(DoorSwingView(run: $run)))
            navRow("Worktop & Splashback", "Link the worktop to the run", "rectangle.portrait", CF.blue,
                   dest: AnyView(WorktopView(run: $run)))
        }
    }

    private var captureLinks: some View {
        VStack(spacing: 10) {
            navRow("Wall Dimensions", "Edit wall size and corners", "arrow.up.left.and.arrow.down.right", CF.blue,
                   dest: AnyView(WallDimensionsEdit(run: $run)))
            navRow("Run Photo Markup", "Photo the wall and mark services", "camera.fill", CF.blue,
                   dest: AnyView(PhotoMarkupView(run: $run)))
            navRow("Defect & Fit Notes", "Log gaps and clashes (\(run.defects.count))", "exclamationmark.triangle.fill", CF.danger,
                   dest: AnyView(DefectNotesView(run: $run)))
        }
    }

    private var outputLinks: some View {
        VStack(spacing: 10) {
            navRow("Layout Board", "Elevation and top plan in one view", "square.grid.2x2.fill", CF.blue,
                   dest: AnyView(LayoutBoardView(run: $run)))
            navRow("Spec & Material List", "Full unit and material list", "list.bullet", CF.blue,
                   dest: AnyView(SpecListView(run: $run)))
            navRow("Cost Estimate", "Add up cabinets, fronts and hardware", "dollarsign.circle.fill", CF.blue,
                   dest: AnyView(CostEstimateView(run: $run)))
            navRow("Order Sheet", "Build the order for cabinets and fronts", "doc.text.fill", CF.orange, hot: true,
                   dest: AnyView(OrderSheetView(run: $run)))
            navRow("Approval & Reports", "Approve and export a clean report", "checkmark.seal.fill", CF.blue,
                   dest: AnyView(ApprovalReportView(run: $run)))
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: {
                settings.haptic(.medium)
                store.duplicate(run)
                showToast("Run duplicated")
            }) {
                HStack { Image(systemName: "doc.on.doc"); Text("Duplicate Run") }
            }.buttonStyle(GhostButtonStyle())

            Button(action: { confirmDelete = true }) {
                HStack { Image(systemName: "trash"); Text("Delete Run") }
            }.buttonStyle(GhostButtonStyle(tint: CF.danger))
        }
        .padding(.top, 6)
    }

    /// The checklist that drives the ring on the run card.
    private var readinessCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(icon: "checklist", title: "Readiness",
                                  subtitle: readinessSubtitle)
                    ReadinessRing(progress: run.readiness, size: 42)
                }
                ForEach(Array(run.readinessSteps.enumerated()), id: \.offset) { _, step in
                    HStack(spacing: 10) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(step.done ? CF.ok : CF.textMute)
                        Text(step.title)
                            .font(.cfBody(13))
                            .foregroundColor(step.done ? CF.textSec : CF.title)
                        Spacer()
                    }
                }
            }
        }
    }

    private var readinessSubtitle: String {
        let steps = run.readinessSteps
        let done = steps.filter(\.done).count
        return "\(done) of \(steps.count) steps done"
    }

    /// Everything the engine wants the fitter to know before the order goes out.
    private var issuesCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "exclamationmark.triangle.fill", title: "Checks",
                              subtitle: run.blockerCount > 0
                                ? "\(run.blockerCount) must be fixed before ordering"
                                : "Nothing blocking — worth a look though")
                ForEach(run.issues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: issue.level.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: issue.level.hex))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.cfHead(13)).foregroundColor(CF.title)
                            Text(issue.detail).font(.cfBody(12)).foregroundColor(CF.textSec)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.cfHead(15)).foregroundColor(CF.textSec)
            .padding(.top, 4)
    }

    private func navRow(_ title: String, _ subtitle: String, _ icon: String, _ accent: Color,
                        hot: Bool = false, dest: AnyView) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(accent.opacity(0.14)).frame(width: 42, height: 42)
                    Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.cfHead(15)).foregroundColor(CF.title)
                        if hot {
                            Text("KEY").font(.system(size: 8, weight: .heavy, design: .rounded))
                                .foregroundColor(.white).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(CF.orange))
                        }
                    }
                    Text(subtitle).font(.cfBody(12)).foregroundColor(CF.textSec).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(CF.textMute)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(CF.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CF.border, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func showToast(_ s: String) {
        withAnimation { toast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Wall dimensions edit (screen 01, edit mode)

struct WallDimensionsEdit: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var toast: String? = nil
    @State private var confirmReset = false

    var body: some View {
        EngineScaffold(title: "Wall Dimension Capture",
                       subtitle: "Enter wall size and verify the corners.",
                       toast: $toast) {
            WallDrawing(run: run).frame(height: 150)
            WallFieldsCard(run: $run)
            HStack(spacing: 10) {
                Button(action: { run.status = .inProgress; flash("Wall locked") }) {
                    HStack { Image(systemName: "lock.fill"); Text("Lock Wall") }
                }.buttonStyle(ActionButtonStyle())
                Button(action: { flash("Measure kept") }) {
                    Text("Keep")
                }.buttonStyle(SecondaryButtonStyle())
            }
            Button(action: { confirmReset = true }) {
                Text("Reset Measurements")
            }.buttonStyle(GhostButtonStyle())
        }
        .alert(isPresented: $confirmReset) {
            Alert(title: Text("Reset measurements?"),
                  message: Text("Wall lengths, ceiling, room depth and tolerance go back to their defaults. Units and appliances are untouched."),
                  primaryButton: .destructive(Text("Reset")) {
                      run.wallLengthCM = 360
                      run.wallBLengthCM = 240
                      run.heightCM = 270
                      run.roomDepthCM = 300
                      run.toleranceCM = 1
                      flash("Measurements reset")
                  },
                  secondaryButton: .cancel())
        }
    }
    private func flash(_ s: String) {
        settings.haptic()
        withAnimation { toast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { toast = nil } }
    }
}

// MARK: - Photo Markup (screen 02)

struct PhotoMarkupView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var showPicker = false
    @State private var newKind = "Socket"
    @State private var newCaption = ""
    @State private var newSeverity: DefectSeverity = .low
    @State private var toast: String? = nil

    private let kinds = ["Window", "Socket", "Water", "Hood vent", "Pipe"]

    var body: some View {
        EngineScaffold(title: "Run Photo Markup",
                       subtitle: "Photo the wall and mark services.",
                       toast: $toast) {
            CFCard {
                VStack(spacing: 12) {
                    ZStack {
                        if let data = run.photo, let ui = UIImage(data: data) {
                            GeometryReader { geo in
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: geo.size.width, height: 200).clipped()
                                    .overlay(markerOverlay(in: geo.size))
                            }.frame(height: 200)
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(CF.bg2).frame(height: 200)
                                .overlay(VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle").font(.system(size: 34)).foregroundColor(CF.textMute)
                                    Text("Add a wall photo").font(.cfBody(13)).foregroundColor(CF.textMute)
                                })
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Button(action: { showPicker = true }) {
                        HStack { Image(systemName: "camera.fill"); Text(run.photo == nil ? "Add Photo" : "Change Photo") }
                    }.buttonStyle(GhostButtonStyle())
                    Text("Pick a service type below, tap the photo to drop a pin, then drag the pin to fine-tune it.")
                        .font(.cfBody(11)).foregroundColor(CF.textMute)
                }
            }

            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "mappin.circle.fill", title: "Mark Service")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(kinds, id: \.self) { k in
                                Button(action: { newKind = k }) {
                                    OptionChip(title: k, selected: newKind == k, accent: CF.orange)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    CFTextField(label: "Caption", text: $newCaption, placeholder: "e.g. socket at 30 cm")
                    fieldLabel("Severity")
                    HStack(spacing: 8) {
                        ForEach(DefectSeverity.allCases) { s in
                            Button(action: { newSeverity = s }) {
                                OptionChip(title: s.title, selected: newSeverity == s, accent: Color(hex: s.hex))
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    Button(action: addMarker) {
                        HStack { Image(systemName: "mappin"); Text("Pin Markup") }
                    }.buttonStyle(ActionButtonStyle())
                }
            }

            if !run.markups.isEmpty {
                CFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(icon: "list.bullet", title: "Pinned (\(run.markups.count))")
                        ForEach(Array(run.markups.enumerated()), id: \.element.id) { idx, m in
                            HStack {
                                ZStack {
                                    Circle().fill(Color(hex: m.severity.hex)).frame(width: 18, height: 18)
                                    Text("\(idx + 1)").font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                Text(m.kind).font(.cfHead(13)).foregroundColor(CF.title)
                                if !m.caption.isEmpty {
                                    Text("• " + m.caption).font(.cfBody(12)).foregroundColor(CF.textSec).lineLimit(1)
                                }
                                Spacer()
                                iconButton("xmark.circle.fill", CF.textMute, "Remove \(m.kind) marker") {
                                    settings.haptic(); run.markups.removeAll { $0.id == m.id }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { img in run.photo = img.cfCompressed() }
        }
    }

    private func markerOverlay(in size: CGSize) -> some View {
        ZStack {
            // Background tap layer sits underneath the pins so dragging a pin does not
            // also drop a new one.
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    // Only a real tap adds a pin; a swipe was someone scrolling.
                    let moved = abs(v.translation.width) + abs(v.translation.height)
                    guard moved < 12 else { return }
                    pin(at: v.location, in: size)
                })

            ForEach(Array(run.markups.enumerated()), id: \.element.id) { idx, m in
                ZStack {
                    Circle().fill(Color(hex: m.severity.hex)).frame(width: 26, height: 26)
                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5).frame(width: 26, height: 26)
                    Text("\(idx + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
                .position(x: CGFloat(m.x) * size.width, y: CGFloat(m.y) * size.height)
                .gesture(DragGesture(minimumDistance: 2).onChanged { v in
                    move(m, to: v.location, in: size)
                })
                .accessibility(label: Text("\(m.kind) marker \(idx + 1)"))
            }
        }
    }

    private func pin(at point: CGPoint, in size: CGSize) {
        let x = min(1, max(0, Double(point.x / size.width)))
        let y = min(1, max(0, Double(point.y / size.height)))
        run.markups.append(ServiceMarkup(kind: newKind, caption: newCaption,
                                         severity: newSeverity, x: x, y: y))
        newCaption = ""
        settings.haptic()
    }

    private func move(_ m: ServiceMarkup, to point: CGPoint, in size: CGSize) {
        guard let i = run.markups.firstIndex(where: { $0.id == m.id }) else { return }
        run.markups[i].x = min(1, max(0, Double(point.x / size.width)))
        run.markups[i].y = min(1, max(0, Double(point.y / size.height)))
    }

    private func addMarker() {
        settings.haptic()
        // Centre pin, then the user drags it where it belongs.
        run.markups.append(ServiceMarkup(kind: newKind, caption: newCaption, severity: newSeverity,
                                        x: 0.5, y: 0.5))
        newCaption = ""
        flash(run.photo == nil ? "Pinned — add a photo to place it" : "Markup pinned — drag it into place")
    }
    private func fieldLabel(_ s: String) -> some View {
        HStack { Text(s.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(CF.textMute); Spacer() }
    }
    private func flash(_ s: String) {
        withAnimation { toast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { toast = nil } }
    }
}

// MARK: - Defect & Fit Notes (screen 16)

struct DefectNotesView: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var run: KitchenRun
    @State private var showPicker = false
    @State private var draftPhoto: Data? = nil
    @State private var issueType = "Gap at wall"
    @State private var severity: DefectSeverity = .medium
    @State private var fix = ""
    @State private var toast: String? = nil

    private let issues = ["Gap at wall", "Misaligned front", "Door clash", "Uneven plinth", "Scratched panel", "Wrong width"]

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        EngineScaffold(title: "Defect & Fit Note",
                       subtitle: "Log gaps, misaligned fronts and clashes.",
                       toast: $toast) {
            CFCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "exclamationmark.triangle.fill", title: "New Issue")
                    if let data = draftPhoto, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill().frame(height: 120).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button(action: { showPicker = true }) {
                        HStack { Image(systemName: "camera.fill"); Text(draftPhoto == nil ? "Add Photo" : "Change Photo") }
                    }.buttonStyle(GhostButtonStyle())

                    fieldLabel("Issue Type")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(issues, id: \.self) { i in
                                Button(action: { issueType = i }) {
                                    OptionChip(title: i, selected: issueType == i, accent: CF.danger)
                                }.buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    fieldLabel("Severity")
                    HStack(spacing: 8) {
                        ForEach(DefectSeverity.allCases) { s in
                            Button(action: { severity = s }) {
                                OptionChip(title: s.title, selected: severity == s, accent: Color(hex: s.hex))
                            }.buttonStyle(PlainButtonStyle())
                        }
                    }
                    CFTextField(label: "Fix Action", text: $fix, placeholder: "e.g. add 5 mm scribe filler")
                    Button(action: pin) {
                        HStack { Image(systemName: "mappin"); Text("Pin Issue") }
                    }.buttonStyle(ActionButtonStyle())
                }
            }

            if run.defects.isEmpty {
                CFCard { Text("No defects logged yet.").font(.cfBody(13)).foregroundColor(CF.textMute)
                    .frame(maxWidth: .infinity).padding(.vertical, 8) }
            } else {
                ForEach(run.defects) { d in
                    CFCard {
                        HStack(spacing: 12) {
                            if let data = d.photo, let ui = UIImage(data: data) {
                                Image(uiImage: ui).resizable().scaledToFill().frame(width: 54, height: 54)
                                    .clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                            } else {
                                ZStack { RoundedRectangle(cornerRadius: 9).fill(Color(hex: d.severity.hex).opacity(0.15))
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color(hex: d.severity.hex)) }
                                    .frame(width: 54, height: 54)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(d.issueType).font(.cfHead(14)).foregroundColor(CF.title)
                                if !d.fixAction.isEmpty {
                                    Text(d.fixAction).font(.cfBody(12)).foregroundColor(CF.textSec).lineLimit(2)
                                }
                                Text(DefectNotesView.dateFormatter.string(from: d.date))
                                    .font(.cfBody(11)).foregroundColor(CF.textMute)
                            }
                            Spacer()
                            VStack(spacing: 6) {
                                StatusPill(text: d.severity.title, hex: d.severity.hex)
                                iconButton("trash", CF.danger, "Delete \(d.issueType) note", size: 16) {
                                    settings.haptic(); run.defects.removeAll { $0.id == d.id }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) { PhotoPicker { img in draftPhoto = img.cfCompressed() } }
    }

    private func pin() {
        settings.haptic()
        run.defects.insert(DefectNote(issueType: issueType, severity: severity, fixAction: fix,
                                      photo: draftPhoto, date: Date()), at: 0)
        draftPhoto = nil; fix = ""
        withAnimation { toast = "Issue pinned" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { toast = nil } }
    }
    private func fieldLabel(_ s: String) -> some View {
        HStack { Text(s.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(CF.textMute); Spacer() }
    }
}

// MARK: - Engine scaffold (shared chrome for sub-screens)

struct EngineScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @Binding var toast: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            CF.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.cfTitle(24)).foregroundColor(CF.title)
                        Text(subtitle).font(.cfBody(14)).foregroundColor(CF.textSec)
                    }
                    content()
                    TabBottomSpacer()
                }
                .padding(.horizontal, 20).padding(.top, 6)
            }
            if let t = toast {
                ConfirmToast(text: t).padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitle("", displayMode: .inline)
    }
}
