//
//  OnboardingView.swift
//  CabFit
//
//  Four "run-builder" screens. Each has a unique illustrated scene and a unique
//  interactive element (tap, drag, scroll-parallax, long-press). Selections
//  configure settings and create the first run. State saved via hasCompletedOnboarding.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings
    @AppStorage("hasCompletedOnboarding") private var done = false

    @State private var page = 0

    // O1 selections
    @State private var shape: KitchenShape = .singleWall
    @State private var useFreq = "Per kitchen"
    @State private var startMode = "Guided"
    @State private var tapPulse = 0           // tap-to-trigger
    @State private var cornerGlow = false

    // O2 selections
    @State private var wallA: Double = 360
    @State private var wallB: Double = 240
    @State private var ceiling: Double = 270
    @State private var setupMode = "Quick Setup"
    @State private var dragStartLength: Double? = nil

    // O3 selections
    @State private var moduleStd: ModuleStandard = .standard
    @State private var baseHeight: Double = 90
    @State private var reminderStyle = "Standard"
    @State private var workspace = "My Kitchens"
    @State private var scrollParallax: CGFloat = 0

    // O4 selections
    @State private var runTitle = "Kitchen Wall A"
    @State private var photo: Data? = nil
    @State private var runDate = Date()
    @State private var priority: Priority = .normal
    @State private var createMode = "Create Now"
    @State private var showPhoto = false
    @State private var holdProgress: CGFloat = 0

    var body: some View {
        ZStack {
            TowerOnboardingBackground(page: page)

            VStack(spacing: 0) {
                // Top bar: Skip
                HStack {
                    Text("Step \(page + 1) of 4")
                        .font(.cfBody(13)).foregroundColor(CF.textMute)
                    Spacer()
                    Button(action: skip) {
                        Text("Skip").font(.cfHead(15)).foregroundColor(CF.blue)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)

                TabView(selection: $page) {
                    screen1.tag(0)
                    screen2.tag(1)
                    screen3.tag(2)
                    screen4.tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.spring(response: 0.45, dampingFraction: 0.85))

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        Capsule()
                            .fill(i == page ? CF.blue : CF.border)
                            .frame(width: i == page ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7))
                    }
                }
                .padding(.vertical, 12)

                // Primary + Next
                HStack(spacing: 12) {
                    if page > 0 {
                        Button(action: { withAnimation { page -= 1 } }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(CF.blue)
                                .frame(width: 52, height: 52)
                                .background(RoundedRectangle(cornerRadius: 14).fill(CF.bg2))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(CF.border, lineWidth: 1))
                        }
                    }
                    if page < 3 {
                        Button(action: advance) { Text(primaryLabel) }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        holdToCreateButton
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .onDisappear { teardownAnimations() }
    }

    private var primaryLabel: String {
        switch page {
        case 0: return "Enter \(shape.title)"
        case 1: return "Set Wall Lengths"
        case 2: return "Set Cabinet Style"
        default: return "Create Run Record"
        }
    }

    private func advance() {
        settings.haptic()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 }
    }

    // MARK: Screen 1 — Kitchen Shape (tap-to-trigger)

    private var screen1: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                onbHeader(title: "Cab Fit Entry",
                          text: "Turn a kitchen wall into a clear cabinet plan.",
                          icon: "square.grid.2x2.fill")

                // Illustrated scene: cabinets stand up along the chosen shape; tap to replay
                CFCard {
                    VStack(spacing: 12) {
                        Text("Tap the wall to build the run")
                            .font(.cfBody(12)).foregroundColor(CF.textMute)
                        ShapePreview(shape: shape, replayToken: tapPulse, cornerGlow: cornerGlow)
                            .frame(height: 130)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                settings.haptic()
                                tapPulse += 1
                                withAnimation(.easeInOut(duration: 0.5)) { cornerGlow = true }
                            }
                    }
                }

                fieldLabel("Kitchen Shape")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(KitchenShape.allCases) { s in
                        Button(action: {
                            settings.haptic()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                shape = s; tapPulse += 1
                            }
                        }) {
                            OptionTile(title: s.title, systemImage: s.symbol, selected: shape == s)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }

                fieldLabel("Use Frequency")
                chipRow(["Per kitchen", "Weekly jobs", "Daily"], selection: $useFreq)

                fieldLabel("Start Mode")
                chipRow(["Guided", "Quick", "Sample"], selection: $startMode)
            }
            .padding(20)
        }
    }

    // MARK: Screen 2 — Wall lengths (drag gesture)

    private var screen2: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                onbHeader(title: "Wall Lengths",
                          text: "Enter wall lengths to fit the units.",
                          icon: "arrow.left.and.right")

                CFCard {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Wall A").font(.cfBody(13)).foregroundColor(CF.textSec)
                            Spacer()
                            Text(settings.len(wallA)).font(.cfNum(18)).foregroundColor(CF.blue)
                        }
                        // Drag the handle up/down to stretch the wall; the module row rebuilds.
                        Text("Drag the handle ↕ to stretch the wall")
                            .font(.cfBody(11)).foregroundColor(CF.textMute)
                        WallStretchView(lengthCM: wallA, moduleWidth: 60)
                            .frame(height: 96)
                        dragHandle
                    }
                }

                fieldLabel("Setup Style")
                chipRow(["Quick Setup", "Detailed Setup", "Photo First"], selection: $setupMode)

                CFCard {
                    VStack(spacing: 14) {
                        CFStepperRow(label: "Wall A", value: $wallA, step: 10, range: 60...900)
                        Divider().background(CF.divider)
                        CFStepperRow(label: "Wall B", value: $wallB, step: 10, range: 0...900)
                        Divider().background(CF.divider)
                        CFStepperRow(label: "Ceiling Height", value: $ceiling, step: 5, range: 200...340)
                    }
                }
            }
            .padding(20)
        }
    }

    private var dragHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(CF.bg2)
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(CF.blue)
                Text("Slide to resize").font(.cfBody(13)).foregroundColor(CF.textSec)
            }
        }
        .frame(height: 46)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CF.border, lineWidth: 1))
        .gesture(
            DragGesture()
                .onChanged { v in
                    // Anchor on the length the drag started from, then offset from it.
                    if dragStartLength == nil { dragStartLength = wallA }
                    let base = dragStartLength ?? wallA
                    let delta = Double(-v.translation.height) / 2     // up = longer
                    wallA = min(900, max(60, ((base + delta) / 5).rounded() * 5))
                }
                .onEnded { _ in dragStartLength = nil; settings.haptic() }
        )
    }

    // MARK: Screen 3 — Cabinet style (scroll-driven parallax)

    private var screen3: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                onbHeader(title: "Cabinet Style & Context",
                          text: "Describe the cabinet style and context.",
                          icon: "square.stack.3d.up")

                // Scroll-driven: preview scales/parallaxes with scroll offset.
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                                           value: geo.frame(in: .named("o3")).minY)
                }
                .frame(height: 0)

                CFCard {
                    VStack(spacing: 10) {
                        Text("Module width preview").font(.cfBody(12)).foregroundColor(CF.textMute)
                        ModuleStandardPreview(standard: moduleStd, baseHeight: baseHeight)
                            .frame(height: 110)
                            .scaleEffect(1 + min(0.12, max(-0.06, scrollParallax / 1400)))
                            .offset(y: scrollParallax / 30)
                    }
                }

                fieldLabel("Module Standard")
                chipRow(ModuleStandard.allCases.map { $0.title }, selection: Binding(
                    get: { moduleStd.title },
                    set: { t in if let m = ModuleStandard.allCases.first(where: { $0.title == t }) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { moduleStd = m } } }
                ))

                CFCard {
                    CFStepperRow(label: "Base Height", value: $baseHeight, step: 1, range: 70...100)
                }

                fieldLabel("Reminder Style")
                chipRow(["Standard", "Frequent", "Minimal"], selection: $reminderStyle)

                CFTextField(label: "Workspace Name", text: $workspace, placeholder: "My Kitchens")
            }
            .padding(20)
        }
        .coordinateSpace(name: "o3")
        .onPreferenceChange(ScrollOffsetKey.self) { v in scrollParallax = v }
    }

    // MARK: Screen 4 — First run record (long-press gesture)

    private var screen4: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                onbHeader(title: "First Run Record",
                          text: "Create one run now or start empty.",
                          icon: "doc.text.fill")

                CFCard {
                    VStack(spacing: 14) {
                        if let data = photo, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(height: 120).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            FirstRunScene(mode: createMode)
                                .frame(height: 120)
                        }
                        Button(action: { showPhoto = true }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text(photo == nil ? "Add Photo" : "Change Photo")
                            }
                        }.buttonStyle(GhostButtonStyle())
                    }
                }

                fieldLabel("Start Mode")
                chipRow(["Create Now", "Use Sample", "Start Empty"], selection: $createMode)

                CFTextField(label: "Run Title", text: $runTitle, placeholder: "Kitchen Wall A")

                CFCard {
                    HStack {
                        Text("Date").font(.cfBody(14)).foregroundColor(CF.text)
                        Spacer()
                        DatePicker("", selection: $runDate, displayedComponents: .date)
                            .labelsHidden()
                            .accentColor(CF.blue)
                    }
                }

                fieldLabel("Priority")
                chipRow(Priority.allCases.map { $0.title }, selection: Binding(
                    get: { priority.title },
                    set: { t in if let p = Priority.allCases.first(where: { $0.title == t }) { priority = p } }
                ))
            }
            .padding(20)
        }
        .sheet(isPresented: $showPhoto) {
            PhotoPicker { img in photo = img.cfCompressed() }
        }
    }

    // Hold-to-create (unique gesture for screen 4)
    private var holdToCreateButton: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14).fill(CF.blue.opacity(0.25))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(gradient: Gradient(colors: [CF.orange, CF.orangeHi]),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * holdProgress)
            }
            HStack {
                Spacer()
                Image(systemName: "hand.tap.fill").foregroundColor(.white)
                Text("Hold to Create Run").font(.cfHead(16)).foregroundColor(.white)
                Spacer()
            }
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.7)
                .onChanged { _ in
                    withAnimation(.linear(duration: 0.7)) { holdProgress = 1 }
                }
                .onEnded { _ in finish() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onEnded { _ in
                if holdProgress < 1 { withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 } }
            }
        )
    }

    // MARK: Shared bits

    private func onbHeader(title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(CF.orange.opacity(0.16)).frame(width: 52, height: 52)
                Image(systemName: icon).font(.system(size: 24, weight: .bold)).foregroundColor(CF.orange)
            }
            Text(title).font(.cfTitle(27)).foregroundColor(CF.title)
            Text(text).font(.cfBody(15)).foregroundColor(CF.textSec)
            }
            Spacer(minLength: 0)
            TowerAccent(index: page + 1, size: 66, opacity: 0.95)
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(CF.textMute)
    }

    private func chipRow(_ options: [String], selection: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    Button(action: { settings.haptic(); selection.wrappedValue = opt }) {
                        OptionChip(title: opt, selected: selection.wrappedValue == opt)
                    }.buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: Completion

    private func finish() {
        settings.haptic(.medium)
        settings.defaultStandard = moduleStd
        settings.defaultBaseHeight = baseHeight
        settings.reminderStyle = reminderStyle

        switch createMode {
        case "Use Sample":
            store.loadSample()
        case "Start Empty":
            store.addRun(blankRun())
        default: // Create Now
            store.addRun(builtRun())
        }
        withAnimation(.easeInOut(duration: 0.3)) { done = true }
    }

    private func skip() {
        settings.haptic()
        withAnimation(.easeInOut(duration: 0.3)) { done = true }
    }

    private func blankRun() -> KitchenRun {
        var run = KitchenRun()
        run.title = runTitle.isEmpty ? "New Run" : runTitle
        run.shape = shape
        run.wallLengthCM = wallA
        run.wallBLengthCM = wallB
        run.heightCM = ceiling
        run.roomDepthCM = max(180, wallB > 0 ? wallB : 300)
        run.baseHeightCM = baseHeight
        run.moduleStandard = moduleStd
        run.priority = priority
        run.dateCreated = runDate
        run.photo = photo
        run.currency = settings.currency
        return run
    }

    private func builtRun() -> KitchenRun {
        var run = blankRun()
        if run.cornerCount > 0 {
            run.cornerType = .internal90
            // Start with a workable corner rather than handing the user a run that
            // immediately fails its own checks.
            run.cornerChoice = .carousel
        }
        run.rebuildBaseRun(snapToTolerance: true)
        run.fillers = KitchenRun.evenFillers(leftover: max(0, run.leftoverCM), count: 2,
                                             corner: run.cornerType != .none)
        run.status = .inProgress
        return run
    }

    private func teardownAnimations() {
        cornerGlow = false
        holdProgress = 0
        dragStartLength = nil
        scrollParallax = 0
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Illustrated scenes

/// O1 — cabinets rising along the selected shape, corner highlighted yellow.
struct ShapePreview: View {
    let shape: KitchenShape
    let replayToken: Int
    let cornerGlow: Bool
    @State private var raised = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch shape {
                case .singleWall:
                    cabinetRow(count: 6, in: CGRect(x: 20, y: geo.size.height - 50, width: geo.size.width - 40, height: 40))
                case .galley:
                    cabinetRow(count: 5, in: CGRect(x: 20, y: 18, width: geo.size.width - 40, height: 32))
                    cabinetRow(count: 5, in: CGRect(x: 20, y: geo.size.height - 46, width: geo.size.width - 40, height: 32))
                case .lShape:
                    cabinetRow(count: 5, in: CGRect(x: 20, y: geo.size.height - 50, width: geo.size.width - 70, height: 40))
                    cornerMark(at: CGPoint(x: geo.size.width - 38, y: geo.size.height - 50))
                    cabinetColumn(count: 2, in: CGRect(x: geo.size.width - 50, y: geo.size.height - 96, width: 32, height: 50))
                case .uShape:
                    cabinetColumn(count: 2, in: CGRect(x: 18, y: 20, width: 30, height: 64))
                    cabinetRow(count: 4, in: CGRect(x: 54, y: geo.size.height - 48, width: geo.size.width - 108, height: 38))
                    cabinetColumn(count: 2, in: CGRect(x: geo.size.width - 48, y: 20, width: 30, height: 64))
                    cornerMark(at: CGPoint(x: 36, y: geo.size.height - 48))
                    cornerMark(at: CGPoint(x: geo.size.width - 34, y: geo.size.height - 48))
                }
            }
        }
        .onAppear { animateIn() }
        .onChange(of: replayToken) { _ in raised = false; animateIn() }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05)) { raised = true }
    }

    private func cabinetRow(count: Int, in rect: CGRect) -> some View {
        let gap: CGFloat = 4
        let w = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        return ForEach(0..<count, id: \.self) { i in
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(gradient: Gradient(colors: [CF.blueHi, CF.blue]),
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: rect.height)
                .scaleEffect(y: raised ? 1 : 0.05, anchor: .bottom)
                .position(x: rect.minX + w / 2 + CGFloat(i) * (w + gap), y: rect.midY)
        }
    }

    private func cabinetColumn(count: Int, in rect: CGRect) -> some View {
        let gap: CGFloat = 4
        let h = (rect.height - gap * CGFloat(count - 1)) / CGFloat(count)
        return ForEach(0..<count, id: \.self) { i in
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(gradient: Gradient(colors: [CF.blueHi, CF.blue]),
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: rect.width, height: h)
                .scaleEffect(raised ? 1 : 0.05, anchor: .center)
                .position(x: rect.midX, y: rect.minY + h / 2 + CGFloat(i) * (h + gap))
        }
    }

    private func cornerMark(at p: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(CF.yellow)
            .frame(width: 16, height: 16)
            .opacity(cornerGlow ? 1 : 0.5)
            .shadow(color: CF.yellow.opacity(cornerGlow ? 0.7 : 0), radius: 6)
            .position(p)
    }
}

/// O2 — a wall that visually fits N 60-cm modules; rebuilds as length changes.
struct WallStretchView: View {
    let lengthCM: Double
    let moduleWidth: Double
    var moduleCount: Int { max(0, Int(lengthCM / moduleWidth)) }
    var leftover: Double { lengthCM - Double(moduleCount) * moduleWidth }

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width
            let denom = max(lengthCM, 1)
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<moduleCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(gradient: Gradient(colors: [CF.blueHi, CF.blue]),
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: CGFloat(moduleWidth / denom) * usable, height: 56)
                    }
                    if leftover > 4 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(CF.yellow.opacity(0.2))
                            DiagonalHatch(spacing: 5).stroke(CF.yellow, lineWidth: 1.3)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(width: max(4, CGFloat(leftover / denom) * usable), height: 56)
                    }
                }
                Rectangle().fill(CF.blueAct).frame(height: 3)
                HStack {
                    Text("\(moduleCount) modules").font(.cfBody(11)).foregroundColor(CF.blue)
                    Spacer()
                    if leftover > 4 {
                        Text("filler " + String(format: "%.0f cm", leftover))
                            .font(.cfBody(11)).foregroundColor(Color(hex: "8A6D10"))
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8))
    }
}

/// O3 — preview of module widths for the selected standard.
struct ModuleStandardPreview: View {
    let standard: ModuleStandard
    let baseHeight: Double
    var body: some View {
        GeometryReader { geo in
            let widths = standard.widths
            let total = widths.reduce(0, +)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // worktop driven by base height
                Rectangle().fill(CF.textSec)
                    .frame(height: 6)
                    .padding(.bottom, CGFloat((baseHeight - 70) / 30) * 10 + 4)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<widths.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(gradient: Gradient(colors: [CF.blueHi, CF.blue]),
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: CGFloat(widths[i] / total) * (geo.size.width - 30), height: 52)
                            .overlay(Text(String(format: "%.0f", widths[i]))
                                        .font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8))
    }
}

/// O4 — scene that reflects the chosen start mode.
struct FirstRunScene: View {
    let mode: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(CF.bg2)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(gradient: Gradient(colors: [CF.blueHi, CF.blue]),
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: i == 2 ? 64 : 44)
                }
                if mode == "Use Sample" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).stroke(CF.orange, lineWidth: 2)
                        Image(systemName: "snowflake").foregroundColor(CF.orange).font(.system(size: 14))
                    }.frame(width: 26, height: 70)
                }
            }
            if mode == "Start Empty" {
                Text("Empty layout").font(.cfBody(12)).foregroundColor(CF.textMute)
                    .padding(6).background(CF.card.opacity(0.85)).cornerRadius(8)
            }
        }
    }
}
