//
//  SettingsView.swift
//  CabFit
//
//  Every control here is wired: theme applies live, units/currency reformat the
//  whole app, defaults feed new runs, and reminders call UNUserNotificationCenter.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var notifier: NotificationManager

    @State private var reminderDates: [String: Date] = [:]
    @State private var showWipeConfirm = false
    @State private var showDiscardConfirm = false
    @State private var showImporter = false
    @State private var pendingImport: Data? = nil
    @State private var exportURL: URL? = nil
    @State private var showExport = false
    @State private var toast: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            CF.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    appearanceCard
                    measurementCard
                    defaultsCard
                    remindersCard
                    dataCard
                    aboutCard
                    TabBottomSpacer()
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            if let t = toast { ConfirmToast(text: t).padding(.bottom, 30)
                .transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .navigationBarTitle("Settings", displayMode: .inline)
        .onAppear { notifier.refreshAuthorization() }
        .actionSheet(isPresented: $showWipeConfirm) {
            ActionSheet(title: Text("Delete all runs?"),
                        message: Text("This removes every kitchen run from this device. It cannot be undone."),
                        buttons: [
                            .destructive(Text("Delete everything")) {
                                store.wipeAll(); flash("All runs deleted")
                            },
                            .cancel()
                        ])
        }
        .sheet(isPresented: $showExport) {
            if let url = exportURL { ActivityView(items: [url]) }
        }
        .sheet(isPresented: $showImporter) {
            JSONImporter { url in receiveImport(url) }
        }
        .alert(isPresented: $showDiscardConfirm) {
            Alert(title: Text("Discard the unreadable file?"),
                  message: Text("Export the raw backup first if you want to keep it — this can't be undone."),
                  primaryButton: .destructive(Text("Discard")) {
                      store.discardUnreadableBackup(); flash("Starting fresh")
                  },
                  secondaryButton: .cancel())
        }
        // Importing can replace everything, so the choice is explicit.
        .actionSheet(item: importSheetBinding) { payload in
            ActionSheet(title: Text("Import \(payload.count) run\(payload.count == 1 ? "" : "s")?"),
                        message: Text("Add them to the \(store.runs.count) run\(store.runs.count == 1 ? "" : "s") already here, or replace everything."),
                        buttons: [
                            .default(Text("Add to my runs")) { commitImport(payload.data, mode: .merge) },
                            .destructive(Text("Replace everything")) { commitImport(payload.data, mode: .replace) },
                            .cancel { pendingImport = nil }
                        ])
        }
    }

    // MARK: Import

    /// Wraps the staged file so `actionSheet(item:)` can show how much is coming in.
    private struct ImportPayload: Identifiable {
        let id = UUID()
        let data: Data
        let count: Int
    }

    private var importSheetBinding: Binding<ImportPayload?> {
        Binding(
            get: {
                guard let data = pendingImport,
                      let runs = try? JSONDecoder().decode([KitchenRun].self, from: data)
                else { return nil }
                return ImportPayload(data: data, count: runs.count)
            },
            set: { if $0 == nil { pendingImport = nil } }
        )
    }

    private func receiveImport(_ url: URL) {
        // Files handed over by the document picker are security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { flash("Couldn't read that file"); return }
        guard (try? JSONDecoder().decode([KitchenRun].self, from: data)) != nil else {
            flash("That isn't a Cab Fit export"); return
        }
        pendingImport = data
    }

    private func commitImport(_ data: Data, mode: DataStore.ImportMode) {
        settings.haptic(.medium)
        pendingImport = nil
        do {
            let n = try store.importRuns(from: data, mode: mode)
            flash("Imported \(n) run\(n == 1 ? "" : "s")")
        } catch {
            flash("Import failed")
        }
    }

    private func exportRawBackup() {
        settings.haptic()
        guard let data = store.unreadableBackup,
              let text = String(data: data, encoding: .utf8),
              let url = FileExporter.write(text, name: "CabFit-RawBackup", ext: "json") else {
            flash("No backup found"); return
        }
        exportURL = url; showExport = true
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "paintbrush.fill", title: "Appearance",
                              subtitle: "Theme applies across the whole app")
                HStack(spacing: 8) {
                    ForEach(ThemeMode.allCases) { mode in
                        Button(action: {
                            settings.haptic()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { settings.theme = mode }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: mode.symbol).font(.system(size: 20, weight: .bold))
                                Text(mode.title).font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(settings.theme == mode ? .white : CF.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 13)
                                .fill(settings.theme == mode ? CF.blue : CF.bg2))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(settings.theme == mode ? CF.blue : CF.border, lineWidth: 1))
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
                Toggle(isOn: $settings.hapticsEnabled) {
                    Text("Haptic feedback").font(.cfBody(14)).foregroundColor(CF.text)
                }.toggleStyle(SwitchToggleStyle(tint: CF.blue))
            }
        }
    }

    // MARK: Measurement

    private var measurementCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "arrow.left.and.right", title: "Measurement",
                              subtitle: "Units and currency")
                label("Units")
                HStack(spacing: 8) {
                    ForEach(UnitSystem.allCases) { u in
                        Button(action: { settings.haptic(); settings.units = u }) {
                            OptionChip(title: u.short, selected: settings.units == u)
                        }.buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                    Text("Sample: " + settings.len(60)).font(.cfBody(12)).foregroundColor(CF.textSec)
                }
                label("Currency")
                HStack(spacing: 8) {
                    ForEach(["$", "€", "£", "₽", "zł"], id: \.self) { c in
                        Button(action: { settings.haptic(); settings.currency = c }) {
                            OptionChip(title: c, selected: settings.currency == c, accent: CF.orange)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Defaults

    private var defaultsCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "square.grid.3x2.fill", title: "New-run Defaults",
                              subtitle: "Used when you create a run")
                label("Module Standard")
                HStack(spacing: 8) {
                    ForEach(ModuleStandard.allCases) { s in
                        Button(action: { settings.haptic(); settings.defaultStandard = s }) {
                            OptionChip(title: s.title, selected: settings.defaultStandard == s)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
                CFStepperRow(label: "Base height", value: $settings.defaultBaseHeight, step: 1, range: 70...100)
                label("Reminder Style")
                HStack(spacing: 8) {
                    ForEach(["Standard", "Frequent", "Minimal"], id: \.self) { r in
                        Button(action: { settings.haptic(); settings.reminderStyle = r }) {
                            OptionChip(title: r, selected: settings.reminderStyle == r, accent: CF.orange)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Reminders (real notifications)

    private var remindersCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "bell.fill", title: "Reminders",
                              subtitle: notifier.authorized ? "\(notifier.pendingCount) scheduled" : "Notifications off")
                Toggle(isOn: Binding(
                    get: { settings.notificationsEnabled && notifier.authorized },
                    set: { on in
                        settings.notificationsEnabled = on
                        if on {
                            notifier.requestAuthorization { granted in
                                if !granted { flash("Enable notifications in iOS Settings") }
                                else { flash("Reminders enabled") }
                            }
                        } else {
                            notifier.cancelAll(); flash("Reminders cancelled")
                        }
                    })) {
                    Text("Enable reminders").font(.cfBody(14)).foregroundColor(CF.text)
                }.toggleStyle(SwitchToggleStyle(tint: CF.orange))

                ForEach(notifier.presets) { preset in
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: preset.symbol).foregroundColor(CF.orange).frame(width: 24)
                            Text(preset.title).font(.cfBody(13)).foregroundColor(CF.title)
                            Spacer()
                        }
                        HStack {
                            DatePicker("", selection: dateBinding(preset.id),
                                       in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().accentColor(CF.blue)
                            Spacer()
                            Button(action: { schedule(preset) }) {
                                Text("Schedule").font(.cfHead(13)).foregroundColor(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule().fill(notifier.authorized ? CF.orange : CF.textMute))
                            }.disabled(!notifier.authorized)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 11).fill(CF.bg2))
                }

                Button(action: { notifier.cancelAll(); flash("All reminders cleared") }) {
                    HStack { Image(systemName: "bell.slash"); Text("Cancel All Reminders") }
                }.buttonStyle(GhostButtonStyle(tint: CF.danger))
            }
        }
    }

    // MARK: Data

    private var dataCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "externaldrive.fill", title: "Data",
                              subtitle: "\(store.runs.count) runs stored locally")

                if store.loadFailed {
                    // The old database couldn't be decoded. It's still on disk, so give
                    // the user a way to get the bytes out before starting over.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The saved runs file couldn't be read. Nothing has been overwritten.")
                            .font(.cfBody(12)).foregroundColor(CF.text)
                        Button(action: exportRawBackup) {
                            HStack { Image(systemName: "arrow.down.doc"); Text("Export Raw Backup") }
                        }.buttonStyle(GhostButtonStyle())
                        Button(action: { showDiscardConfirm = true }) {
                            HStack { Image(systemName: "trash"); Text("Discard and Start Fresh") }
                        }.buttonStyle(GhostButtonStyle(tint: CF.danger))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 11).fill(CF.danger.opacity(0.10)))
                }

                Button(action: exportData) {
                    HStack { Image(systemName: "square.and.arrow.up"); Text("Export Runs (JSON)") }
                }.buttonStyle(GhostButtonStyle())
                Button(action: { showImporter = true }) {
                    HStack { Image(systemName: "square.and.arrow.down"); Text("Import Runs (JSON)") }
                }.buttonStyle(GhostButtonStyle())
                Text("Import adds the runs from a Cab Fit export. Runs already here keep their place; anything that clashes comes in as a copy.")
                    .font(.cfBody(11)).foregroundColor(CF.textMute)
                Button(action: { showWipeConfirm = true }) {
                    HStack { Image(systemName: "trash"); Text("Delete All Runs") }
                }.buttonStyle(GhostButtonStyle(tint: CF.danger))
            }
        }
    }

    private var aboutCard: some View {
        CFCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(icon: "info.circle.fill", title: "About Cab Fit")
                Text("Cab Fit lays out standard cabinet modules along your wall, turns leftovers into even fillers, reserves appliance niches with clearances and checks the sink–hob–fridge triangle.")
                    .font(.cfBody(13)).foregroundColor(CF.textSec)
                Text("Everything is stored locally on this device — no account, no cloud. Export is always your choice.")
                    .font(.cfBody(12)).foregroundColor(CF.textMute)
                Text("Version 1.0").font(.cfBody(12)).foregroundColor(CF.textMute)
            }
        }
    }

    // MARK: Helpers

    private func label(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(CF.textMute)
    }

    private func dateBinding(_ id: String) -> Binding<Date> {
        Binding(
            get: { reminderDates[id] ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())! },
            set: { reminderDates[id] = $0 }
        )
    }

    private func schedule(_ preset: ReminderPreset) {
        settings.haptic(.medium)
        let date = dateBinding(preset.id).wrappedValue
        let ok = notifier.schedule(preset: preset, at: date,
                                   runTitle: store.selectedRun?.title ?? "",
                                   style: settings.reminderStyle)
        flash(ok ? "Reminder scheduled" : "Pick a time in the future")
    }

    private func exportData() {
        settings.haptic()
        guard !store.runs.isEmpty else { flash("No runs to export"); return }
        guard let data = try? store.exportData(),
              let text = String(data: data, encoding: .utf8),
              let url = FileExporter.write(text, name: "CabFit-Runs", ext: "json") else {
            flash("Export failed"); return
        }
        exportURL = url; showExport = true
    }

    private func flash(_ s: String) {
        withAnimation { toast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { toast = nil } }
    }
}
