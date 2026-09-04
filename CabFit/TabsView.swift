//
//  TabsView.swift
//  CabFit
//
//  The Units, Appliances and Triangle tabs. Each operates on the run selected
//  in the shared RunPickerBar and links into the full engine screens.
//

import SwiftUI

// MARK: - Units tab

struct UnitsTab: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationView {
            ZStack {
                CF.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        TabTitleHeader(title: "Units", subtitle: "Modules placed across the run")
                        RunPickerBar()

                        if let binding = store.selectedBinding {
                            let run = binding.wrappedValue
                            CFCard {
                                VStack(spacing: 12) {
                                    WallStripView(run: run, height: 64)
                                    HStack(spacing: 10) {
                                        MetricBadge(value: "\(run.units.filter { $0.type == .base }.count)", label: "Base", hex: "1F6FE0")
                                        MetricBadge(value: "\(run.units.filter { $0.type == .wall }.count)", label: "Wall", hex: "5C9BF0")
                                        MetricBadge(value: "\(run.units.filter { $0.type == .tall }.count)", label: "Tall", hex: "F77A1E")
                                        MetricBadge(value: settings.lenValue(run.baseUnitsTotalCM),
                                                    label: "Run \(settings.units.short)", hex: "2FA85A")
                                    }
                                }
                            }

                            if run.units.isEmpty {
                                CFCard { Text("No units yet — open the picker or auto-build the run.")
                                    .font(.cfBody(13)).foregroundColor(CF.textMute)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10) }
                            } else {
                                CFCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        SectionHeader(icon: "square.grid.3x2.fill", title: "Unit List")
                                        ForEach(run.units) { u in
                                            HStack(spacing: 10) {
                                                Image(systemName: u.function.symbol).foregroundColor(CF.blue).frame(width: 22)
                                                Text(u.function.title).font(.cfBody(13)).foregroundColor(CF.title)
                                                Spacer()
                                                Text("\(u.type.title) • \(settings.lenValue(u.widthCM))")
                                                    .font(.cfBody(12)).foregroundColor(CF.textSec)
                                            }
                                        }
                                    }
                                }
                            }

                            NavigationLink(destination: ModulePickerView(run: binding)) {
                                actionRow("Open Module Picker", "Add base, wall and tall units", "square.stack.3d.up")
                            }.buttonStyle(PlainButtonStyle())
                            NavigationLink(destination: RunBuilderView(run: binding)) {
                                actionRow("Open Run Builder", "Auto-fit modules along the wall", "square.grid.3x2.fill")
                            }.buttonStyle(PlainButtonStyle())
                        } else {
                            NoRunEmptyState(message: "Create a run in the Runs tab to lay out cabinet modules.")
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
    }
}

// MARK: - Appliances tab

struct AppliancesTab: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationView {
            ZStack {
                CF.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        TabTitleHeader(title: "Appliances", subtitle: "Slots, clearances and services")
                        RunPickerBar()

                        if let binding = store.selectedBinding {
                            let run = binding.wrappedValue
                            CFCard {
                                VStack(spacing: 12) {
                                    WallStripView(run: run, height: 64)
                                    HStack(spacing: 10) {
                                        MetricBadge(value: "\(run.appliances.count)", label: "Slots", hex: "F77A1E")
                                        MetricBadge(value: settings.lenValue(run.applianceTotalCM), label: "Reserved", hex: "F77A1E")
                                        MetricBadge(value: "\(run.appliances.filter { $0.hasWater }.count)", label: "Water", hex: "1F6FE0")
                                        MetricBadge(value: "\(run.appliances.filter { $0.hasPower }.count)", label: "Power", hex: "F6BE24")
                                    }
                                }
                            }

                            if run.appliances.isEmpty {
                                CFCard { Text("No appliance slots reserved yet.")
                                    .font(.cfBody(13)).foregroundColor(CF.textMute)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10) }
                            } else {
                                CFCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        SectionHeader(icon: "flame.fill", title: "Reserved Slots")
                                        ForEach(run.appliances) { a in
                                            HStack(spacing: 10) {
                                                ZStack { RoundedRectangle(cornerRadius: 7).stroke(CF.orange, lineWidth: 2).frame(width: 30, height: 30)
                                                    Image(systemName: a.kind.symbol).font(.system(size: 13)).foregroundColor(CF.orange) }
                                                Text(a.kind.title).font(.cfHead(13)).foregroundColor(CF.title)
                                                Spacer()
                                                if a.hasWater { Image(systemName: "drop.fill").font(.system(size: 11)).foregroundColor(CF.blue) }
                                                if a.hasPower { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundColor(CF.orange) }
                                                Text(settings.lenValue(a.totalWidthCM)).font(.cfNum(13)).foregroundColor(CF.orange)
                                            }
                                        }
                                    }
                                }
                            }

                            NavigationLink(destination: ApplianceSlotsView(run: binding)) {
                                actionRow("Open Appliance Slots", "Reserve slots with clearances", "flame.fill")
                            }.buttonStyle(PlainButtonStyle())
                        } else {
                            NoRunEmptyState(message: "Create a run in the Runs tab to reserve appliance slots.")
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
    }
}

// MARK: - Triangle tab

struct TriangleTab: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationView {
            ZStack {
                CF.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        TabTitleHeader(title: "Triangle", subtitle: "Sink–hob–fridge ergonomics")
                        RunPickerBar()

                        if let binding = store.selectedBinding {
                            let run = binding.wrappedValue
                            CFCard {
                                VStack(spacing: 12) {
                                    TriangleCanvas(triangle: binding.triangle).frame(height: 220)
                                    let r = run.scaledTriangle.rating
                                    HStack {
                                        StatusPill(text: r.title, hex: r.hex)
                                        Spacer()
                                        Text("Sum " + settings.len(run.scaledTriangle.sum))
                                            .font(.cfNum(16)).foregroundColor(Color(hex: r.hex))
                                    }
                                    Text(r.advice).font(.cfBody(12)).foregroundColor(CF.textSec)
                                }
                            }

                            CFCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionHeader(icon: "triangle.fill", title: "Legs")
                                    legRow("Sink → Hob", run.scaledTriangle.legSinkHob)
                                    legRow("Hob → Fridge", run.scaledTriangle.legHobFridge)
                                    legRow("Fridge → Sink", run.scaledTriangle.legFridgeSink)
                                }
                            }

                            NavigationLink(destination: WorkTriangleView(run: binding)) {
                                actionRow("Open Work Triangle", "Drag points and evaluate", "triangle.fill")
                            }.buttonStyle(PlainButtonStyle())
                        } else {
                            NoRunEmptyState(message: "Create a run in the Runs tab to check the work triangle.")
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
    }

    private func legRow(_ name: String, _ cm: Double) -> some View {
        HStack {
            Text(name).font(.cfBody(13)).foregroundColor(CF.text)
            Spacer()
            Text(settings.len(cm)).font(.cfNum(14))
                .foregroundColor(cm < 120 || cm > 270 ? CF.warn : CF.ok)
        }
    }
}

// MARK: - Shared action row

func actionRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
    HStack(spacing: 12) {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(CF.orange.opacity(0.14)).frame(width: 44, height: 44)
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(CF.orange)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.cfHead(15)).foregroundColor(CF.title)
            Text(subtitle).font(.cfBody(12)).foregroundColor(CF.textSec)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(CF.textMute)
    }
    .padding(13)
    .background(RoundedRectangle(cornerRadius: 14).fill(CF.card))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(CF.border, lineWidth: 1))
}
