//
//  LaunchView.swift
//  CabFit
//
//  Thematic splash: cabinet modules rise one-by-one along a wall line while an
//  orange fridge niche flashes. Three looping layers (gradient drift, niche flash,
//  logo glow) plus a staged entrance. A single coordinator timer hands off to the
//  app; every looping state is reset in onDisappear so nothing leaks.
//

import SwiftUI

struct LaunchView: View {
    let onFinish: () -> Void

    // Looping layers
    @State private var isVisible = true
    @State private var bgDrift = false      // layer 1: background gradient drift
    @State private var nicheFlash = false   // layer 2: fridge niche flash
    @State private var logoGlow = false     // layer 3: logo glow pulse

    // Staged entrance
    @State private var appeared = false     // cabinets rise (staggered per index)
    @State private var nicheUp = false
    @State private var logoIn = false
    @State private var exiting = false

    // Single coordinator hand-off (cancellable, does not thrash view state)
    @State private var finishWork: DispatchWorkItem? = nil

    private let cabinetWidths: [CGFloat] = [0.7, 1.0, 0.85, 1.1, 0.75]

    var body: some View {
        ZStack {
            // LAYER 1 — drifting background gradient
            LinearGradient(gradient: Gradient(colors: [CF.bg, CF.bg2, CF.bgDeep]),
                           startPoint: bgDrift ? .topLeading : .top,
                           endPoint: bgDrift ? .bottom : .bottomTrailing)
                .ignoresSafeArea()

            BlueprintGrid()
                .stroke(CF.blue.opacity(0.06), lineWidth: 1)
                .ignoresSafeArea()

            TowerAccent(index: 0, size: 190, opacity: 0.23)
                .offset(x: 118, y: -275)

            VStack(spacing: 30) {
                Spacer()

                // LAYER 3 — logo with pulsing glow
                ZStack {
                    Circle()
                        .fill(CF.blue.opacity(0.18))
                        .frame(width: 130, height: 130)
                        .scaleEffect(logoGlow ? 1.18 : 0.9)
                        .opacity(logoGlow ? 0.5 : 0.25)
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(gradient: Gradient(colors: [CF.blue, CF.blueAct]),
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 96, height: 96)
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: CF.blueGlow, radius: 16, y: 8)
                }
                .scaleEffect(logoIn ? 1 : 0.4)
                .opacity(logoIn ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Cab Fit")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(CF.title)
                    Text("Fit the kitchen, wall to wall.")
                        .font(.cfBody(15))
                        .foregroundColor(CF.textSec)
                }
                .opacity(logoIn ? 1 : 0)
                .offset(y: logoIn ? 0 : 16)

                Spacer()

                // LAYER 2 — cabinet run standing up along the wall, with fridge niche
                cabinetRun
                    .padding(.horizontal, 30)

                Spacer()
            }
            .scaleEffect(exiting ? 1.18 : 1)
            .opacity(exiting ? 0 : 1)
        }
        // Three seconds is a long time to look at a splash you've already seen.
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear { start() }
        .onDisappear { teardown() }
        .accessibility(addTraits: .isButton)
        .accessibility(label: Text("Cab Fit. Tap to continue."))
    }

    private func skip() {
        guard isVisible else { return }
        isVisible = false
        finishWork?.cancel(); finishWork = nil
        withAnimation(.easeIn(duration: 0.2)) { exiting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onFinish() }
    }

    private var cabinetRun: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<cabinetWidths.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(gradient: Gradient(colors: [CF.blueHi, CF.blue]),
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 38 * cabinetWidths[i], height: 54)
                        .scaleEffect(y: appeared ? 1 : 0.02, anchor: .bottom)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6)
                                    .delay(0.4 + Double(i) * 0.13))
                }

                // fridge niche (taller, orange flashing outline)
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CF.orange.opacity(nicheFlash ? 0.18 : 0.05))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(CF.orange, lineWidth: nicheFlash ? 3 : 1.5)
                    Image(systemName: "snowflake")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(CF.orange)
                        .opacity(nicheFlash ? 1 : 0.5)
                }
                .frame(width: 42, height: 88)
                .scaleEffect(y: nicheUp ? 1 : 0.02, anchor: .bottom)
                .opacity(nicheUp ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(1.2))
            }
            Rectangle()
                .fill(CF.blueAct)
                .frame(height: 3)
                .padding(.top, 2)
        }
        .frame(height: 96, alignment: .bottom)
    }

    // MARK: Coordinator

    private func start() {
        isVisible = true
        // loops
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { bgDrift = true }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { nicheFlash = true }
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { logoGlow = true }

        // staged entrance (robust, animation-delay driven)
        appeared = true          // cabinets rise with per-index delays
        nicheUp = true           // niche rises (delayed in its modifier)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(1.5)) { logoIn = true }
        withAnimation(.easeIn(duration: 0.4).delay(2.65)) { exiting = true }

        // single coordinator: hand off at 3.0s (cancellable, no per-frame state churn)
        let work = DispatchWorkItem { if isVisible { onFinish() } }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func teardown() {
        isVisible = false
        finishWork?.cancel(); finishWork = nil
        bgDrift = false
        nicheFlash = false
        logoGlow = false
        appeared = false
        nicheUp = false
        logoIn = false
        exiting = false
    }
}

/// Light blueprint grid behind the splash.
struct BlueprintGrid: Shape {
    var spacing: CGFloat = 28
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x <= rect.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height)); x += spacing }
        var y: CGFloat = 0
        while y <= rect.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)); y += spacing }
        return p
    }
}
