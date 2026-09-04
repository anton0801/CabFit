//
//  MainTabView.swift
//  CabFit
//
//  Custom themed tab bar + the five primary tabs.
//

import SwiftUI

struct MainTabView: View {
    @State private var tab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            CF.bg.ignoresSafeArea()

            Group {
                switch tab {
                case 0: RunsTab()
                case 1: UnitsTab()
                case 2: AppliancesTab()
                case 3: TriangleTab()
                default: ReportsTab()
                }
            }

            CFTabBar(selection: $tab)
                .edgesIgnoringSafeArea(.bottom)
        }
    }
}

struct CFTabItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
}

struct CFTabBar: View {
    @Binding var selection: Int
    @EnvironmentObject var settings: AppSettings

    private let items = [
        CFTabItem(title: "Runs", symbol: "rectangle.stack.fill"),
        CFTabItem(title: "Units", symbol: "square.grid.3x2.fill"),
        CFTabItem(title: "Appliances", symbol: "flame.fill"),
        CFTabItem(title: "Triangle", symbol: "triangle.fill"),
        CFTabItem(title: "Reports", symbol: "doc.text.fill")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                Button(action: {
                    settings.haptic()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { selection = idx }
                }) {
                    VStack(spacing: 4) {
                        ZStack {
                            if selection == idx {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(CF.blue.opacity(0.16))
                                    .frame(width: 46, height: 34)
                            }
                            Image(systemName: item.symbol)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(selection == idx ? CF.blue : CF.textMute)
                        }
                        .frame(height: 34)
                        Text(item.title)
                            .font(.system(size: 10, weight: selection == idx ? .bold : .semibold,
                                          design: .rounded))
                            .foregroundColor(selection == idx ? CF.blue : CF.textMute)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            CF.card
                .overlay(Rectangle().fill(CF.border).frame(height: 1), alignment: .top)
                .shadow(color: CF.shadow, radius: 12, y: -2)
                .edgesIgnoringSafeArea(.bottom)
        )
    }
}

// MARK: - Shared header used across tabs

struct TabTitleHeader: View {
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.cfTitle(28)).foregroundColor(CF.title)
                Text(subtitle).font(.cfBody(13)).foregroundColor(CF.textSec)
            }
            Spacer()
            TowerAccent(index: accentIndex, size: 46, opacity: 0.92)
            if let t = trailing { t }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var accentIndex: Int {
        switch title {
        case "Units": return 14       // scaffold
        case "Appliances": return 6   // work light
        case "Triangle": return 9     // tape measure
        case "Reports": return 13     // blueprints
        default: return 0
        }
    }
}

// MARK: - Run picker bar (Units / Appliances / Triangle / Reports operate on a run)

struct RunPickerBar: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        if store.runs.isEmpty {
            EmptyView()
        } else {
            Menu {
                ForEach(store.runs) { run in
                    Button(action: { store.selectedRunID = run.id }) {
                        if store.selectedRunID == run.id {
                            Label(run.title, systemImage: "checkmark")
                        } else {
                            Text(run.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill").foregroundColor(CF.blue)
                    Text(store.selectedRun?.title ?? "Select run")
                        .font(.cfHead(15)).foregroundColor(CF.title)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        .foregroundColor(CF.textMute)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 13).fill(CF.card))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(CF.border, lineWidth: 1))
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Empty state used by tabs without a run

struct NoRunEmptyState: View {
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(CF.blue.opacity(0.12)).frame(width: 90, height: 90)
                TowerAccent(index: 15, size: 78)
            }
            Text("No run selected").font(.cfHead(18)).foregroundColor(CF.title)
            Text(message).font(.cfBody(14)).foregroundColor(CF.textSec)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bottom spacer that clears the tab bar

struct TabBottomSpacer: View {
    var body: some View { Color.clear.frame(height: 104) }
}
