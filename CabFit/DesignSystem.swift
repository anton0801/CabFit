//
//  DesignSystem.swift
//  CabFit
//
//  Colour palette (theme-adaptive), typography, reusable components,
//  the reusable wall-strip canvas, and small UIKit bridges (photo picker, share sheet).
//  Everything here is iOS 14 compatible.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Colour helpers

extension UIColor {
    convenience init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
    /// Dynamic colour that follows light/dark trait (and therefore preferredColorScheme).
    static func dyn(_ light: String, _ dark: String) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hexString: dark) : UIColor(hexString: light)
        }
    }
}

extension Color {
    init(hex: String) { self.init(UIColor(hexString: hex)) }
    static func dyn(_ light: String, _ dark: String) -> Color { Color(UIColor.dyn(light, dark)) }
}

/// Central palette. Light values come straight from the spec; dark values keep the
/// blue-construction identity while satisfying "theme switching changes the whole app".
enum CF {
    // Backgrounds
    static let bg       = Color.dyn("F3F8FD", "0E1726")
    static let bg2      = Color.dyn("E7F0FB", "15213A")
    static let bgDeep   = Color.dyn("DAE8F6", "08101C")
    // Cards
    static let card     = Color.dyn("FFFFFF", "182740")
    static let cardHi   = Color.dyn("F4F9FE", "213354")
    static let border   = Color.dyn("C9DCEF", "2C3F66")
    static let divider  = Color.dyn("E2ECF7", "21304F")
    // Brand
    static let blue     = Color.dyn("1F6FE0", "2F6BFF")
    static let blueAct  = Color.dyn("1557BC", "1E54E6")
    static let blueHi   = Color.dyn("5C9BF0", "6E9BFF")
    static let orange   = Color(hex: "F77A1E")
    static let orangeAct = Color(hex: "E0650C")
    static let orangeHi = Color(hex: "FF9A4D")
    static let yellow   = Color(hex: "F6BE24")
    static let yellowHi = Color(hex: "FFD862")
    // Status
    static let ok       = Color(hex: "2FA85A")
    static let warn     = Color(hex: "F6BE24")
    static let danger   = Color(hex: "EF4444")
    // Text
    static let title    = Color.dyn("102A4A", "EAF1FF")
    static let text     = Color.dyn("14315C", "DCE7FF")
    static let textSec  = Color.dyn("44587A", "A9BCDC")
    static let textMute = Color.dyn("8AA0BE", "647499")
    // Button label colours
    static let onAction = Color(hex: "0E2440")
    static let onSecondary = Color(hex: "1A2E12")
    // Glows
    static let blueGlow = Color(hex: "1F6FE0").opacity(0.18)
    static let orangeGlow = Color(hex: "F77A1E").opacity(0.26)
    static let shadow   = Color.dyn("14315C", "000000").opacity(0.10)
}

// MARK: - Tower Rush-inspired construction artwork

/// A four-scene construction backdrop.  The image is an atlas so the app ships
/// a compact bundle while each onboarding page still gets its own scene.
struct TowerOnboardingBackground: View {
    let page: Int

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            let col = page % 2
            let row = page / 2
            Image("TowerOnboardingAtlas")
                .resizable()
                .interpolation(.high)
                .frame(width: side * 2, height: side * 2)
                .offset(x: col == 0 ? side / 2 : -side / 2,
                        y: row == 0 ? side / 2 : -side / 2)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(
                    LinearGradient(gradient: Gradient(colors: [CF.bg.opacity(0.22), CF.bg.opacity(0.80)]),
                                   startPoint: .top, endPoint: .bottom)
                )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// One of sixteen original site props (hook, helmet, plans, cone, beams,
/// lighting, tools and machinery) cut from a single high-resolution atlas.
/// Keeping this purely decorative ensures the product flow stays unchanged.
struct TowerAccent: View {
    let index: Int
    var size: CGFloat = 44
    var opacity: Double = 1

    var body: some View {
        GeometryReader { _ in
            let clamped = min(15, max(0, index))
            let col = clamped % 4
            let row = clamped / 4
            Image("TowerAccentAtlas")
                .resizable()
                .interpolation(.high)
                .frame(width: size * 4, height: size * 4)
                .offset(x: (1.5 - CGFloat(col)) * size,
                        y: (1.5 - CGFloat(row)) * size)
                .frame(width: size, height: size)
                .clipped()
                .opacity(opacity)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Typography

extension Font {
    static func cfTitle(_ s: CGFloat = 26) -> Font { .system(size: s, weight: .heavy, design: .rounded) }
    static func cfHead(_ s: CGFloat = 18)  -> Font { .system(size: s, weight: .bold, design: .rounded) }
    static func cfBody(_ s: CGFloat = 15)  -> Font { .system(size: s, weight: .medium, design: .rounded) }
    static func cfNum(_ s: CGFloat = 22)   -> Font { .system(size: s, weight: .heavy, design: .rounded) }
}

// MARK: - Card container

struct CFCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CF.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CF.border, lineWidth: 1)
            )
            .shadow(color: CF.shadow, radius: 10, x: 0, y: 6)
    }
}

// MARK: - Button styles

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cfHead(16))
            .foregroundColor(CF.onAction)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(gradient: Gradient(colors: [CF.orange, CF.orangeHi]),
                                         startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: CF.orangeGlow, radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cfHead(16))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(gradient: Gradient(colors: [CF.blue, CF.blueAct]),
                                         startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: CF.blueGlow, radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cfHead(15))
            .foregroundColor(CF.onSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(gradient: Gradient(colors: [CF.yellow, CF.yellowHi]),
                                         startPoint: .top, endPoint: .bottom))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6))
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = CF.blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cfHead(15))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(CF.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(CF.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6))
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    let hex: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: hex))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color(hex: hex).opacity(0.15))
            )
            .overlay(
                Capsule().stroke(Color(hex: hex).opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CF.blue.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(CF.blue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.cfHead(17)).foregroundColor(CF.title)
                if let s = subtitle {
                    Text(s).font(.cfBody(12)).foregroundColor(CF.textSec)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Labeled text field

struct CFTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(CF.textMute)
            TextField(placeholder, text: $text)
                .font(.cfBody(15))
                .foregroundColor(CF.title)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11).fill(CF.bg2))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(CF.border, lineWidth: 1))
        }
    }
}

// MARK: - Stepper row

/// What a stepper's number means. Lengths are stored in centimetres and rendered in
/// whatever unit the user picked, so the number and its suffix always agree.
enum CFStepperKind {
    case length
    case raw(String)     // currency, %, pcs — shown as-is
}

struct CFStepperRow: View {
    @EnvironmentObject private var settings: AppSettings

    let label: String
    @Binding var value: Double
    /// Increment in the stored unit (centimetres for `.length`).
    var step: Double = 5
    /// Allowed range in the stored unit.
    var range: ClosedRange<Double> = 0...10000
    var kind: CFStepperKind = .length

    var body: some View {
        HStack {
            Text(label).font(.cfBody(14)).foregroundColor(CF.text)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                stepButton("minus.circle.fill", CF.blue, -step, "Decrease \(label)")
                Text(display)
                    .font(.cfNum(16)).foregroundColor(CF.title)
                    .frame(minWidth: 72)
                    .lineLimit(1).minimumScaleFactor(0.7)
                stepButton("plus.circle.fill", CF.orange, step, "Increase \(label)")
            }
        }
    }

    private var display: String {
        switch kind {
        case .length:
            return settings.lenValue(value) + " " + settings.units.short
        case .raw(let suffix):
            let n = abs(value.rounded() - value) < 0.05
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            return suffix == "%" || suffix.isEmpty ? n + suffix : n + " " + suffix
        }
    }

    private func stepButton(_ icon: String, _ tint: Color, _ delta: Double,
                            _ accessibility: String) -> some View {
        Button(action: { adjust(delta) }) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(tint)
                // 44pt hit area without changing the drawn size.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibility(label: Text(accessibility))
    }

    private func adjust(_ d: Double) {
        // Nudge onto the step grid so a value that arrived off-grid tidies up.
        let raw = value + d
        let snapped = (raw / step).rounded() * step
        let n = abs(snapped - raw) < step * 0.5 ? snapped : raw
        value = min(range.upperBound, max(range.lowerBound, n))
    }
}

// MARK: - Selectable option card / chip

struct OptionChip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    var accent: Color = CF.blue
    var body: some View {
        HStack(spacing: 6) {
            if let s = systemImage {
                Image(systemName: s).font(.system(size: 13, weight: .bold))
            }
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundColor(selected ? .white : CF.text)
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(
            Capsule().fill(selected ? accent : CF.bg2)
        )
        .overlay(
            Capsule().stroke(selected ? accent : CF.border, lineWidth: 1)
        )
    }
}

struct OptionTile: View {
    let title: String
    let systemImage: String
    let selected: Bool
    var accent: Color = CF.blue
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(selected ? .white : accent)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(selected ? .white : CF.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(selected ? accent : CF.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(selected ? accent : CF.border, lineWidth: selected ? 0 : 1)
        )
        .shadow(color: selected ? accent.opacity(0.3) : CF.shadow, radius: 8, y: 4)
    }
}

// MARK: - Metric badge

struct MetricBadge: View {
    let value: String
    let label: String
    var hex: String = "1F6FE0"
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.cfNum(20)).foregroundColor(Color(hex: hex))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(CF.textMute)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color(hex: hex).opacity(0.10)))
    }
}

// MARK: - Diagonal hatch shape (for fillers)

struct DiagonalHatch: Shape {
    var spacing: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.height))
            p.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return p
    }
}

// MARK: - Wall strip canvas (reusable layout drawing)

struct WallSegment: Identifiable {
    enum Role { case base, wall, appliance, filler, corner }
    let id = UUID()
    let role: Role
    let widthCM: Double
    let label: String
    let symbol: String?
}

struct WallStripView: View {
    let run: KitchenRun
    var height: CGFloat = 64
    var showLabels: Bool = true

    private var segments: [WallSegment] {
        var segs: [WallSegment] = []
        if run.cornerConsumeCM > 0 {
            segs.append(WallSegment(role: .corner, widthCM: run.cornerConsumeCM,
                                    label: "Corner", symbol: "arrow.turn.up.right"))
        }
        for u in run.units where u.type != .wall {
            segs.append(WallSegment(role: .base, widthCM: u.widthCM,
                                    label: u.function.title, symbol: u.function.symbol))
        }
        for a in run.appliances {
            segs.append(WallSegment(role: .appliance, widthCM: a.totalWidthCM,
                                    label: a.kind.title, symbol: a.kind.symbol))
        }
        for f in run.fillers {
            segs.append(WallSegment(role: .filler, widthCM: f.widthCM, label: "Filler", symbol: nil))
        }
        return segs
    }

    private var denominator: Double {
        let total = segments.reduce(0) { $0 + $1.widthCM }
        return max(run.totalWallCM, total, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let used = segments.reduce(0) { $0 + $1.widthCM }
            let hasTail = run.totalWallCM - used > 0.5
            // The 2pt gaps between segments are real width too — leaving them out of
            // the scale made the strip run past the edge of its card.
            let gapCount = max(0, segments.count - 1) + (hasTail ? 1 : 0)
            let usable = max(1, geo.size.width - CGFloat(gapCount) * 2)
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(segments) { seg in
                        segmentView(seg, width: CGFloat(seg.widthCM / denominator) * usable)
                    }
                    // trailing empty gap if wall longer than content
                    if hasTail {
                        let w = CGFloat((run.totalWallCM - used) / denominator) * usable
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundColor(CF.textMute.opacity(0.5))
                            .frame(width: max(2, w))
                    }
                }

                // Where the wall actually ends. Without this the strip just rescales and
                // an overflowing run looks like it fits.
                if used > run.totalWallCM + 0.5 {
                    let x = wallEndX(usable: usable)
                    Rectangle()
                        .fill(CF.danger)
                        .frame(width: 2)
                        .offset(x: x - 1)
                    Rectangle()
                        .fill(CF.danger.opacity(0.18))
                        .frame(width: max(2, usable - x))
                        .offset(x: x)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibility(label: Text(accessibilitySummary))
    }

    /// Where the wall ends in view space, counting the gaps drawn before it.
    private func wallEndX(usable: CGFloat) -> CGFloat {
        var remaining = run.totalWallCM
        var x: CGFloat = 0
        for seg in segments {
            if remaining <= 0 { break }
            let take = min(seg.widthCM, remaining)
            x += CGFloat(take / denominator) * usable
            remaining -= take
            if remaining > 0 { x += 2 }   // the gap after a fully-drawn segment
        }
        return x
    }

    private var accessibilitySummary: String {
        let used = segments.reduce(0) { $0 + $1.widthCM }
        let fit = used > run.totalWallCM + 0.5
            ? String(format: "overflowing by %.0f centimetres", used - run.totalWallCM)
            : String(format: "%.0f centimetres free", run.totalWallCM - used)
        return "Wall layout, \(segments.count) items, \(fit)"
    }

    @ViewBuilder
    private func segmentView(_ seg: WallSegment, width: CGFloat) -> some View {
        let w = max(3, width)
        ZStack {
            switch seg.role {
            case .base:
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(gradient: Gradient(colors: [CF.blue, CF.blueAct]),
                                         startPoint: .top, endPoint: .bottom))
            case .wall:
                RoundedRectangle(cornerRadius: 6).fill(CF.blueHi)
            case .appliance:
                RoundedRectangle(cornerRadius: 6).fill(CF.orange.opacity(0.10))
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CF.orange, lineWidth: 2)
            case .filler:
                RoundedRectangle(cornerRadius: 4).fill(CF.yellow.opacity(0.18))
                DiagonalHatch(spacing: 5)
                    .stroke(CF.yellow, lineWidth: 1.4)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                RoundedRectangle(cornerRadius: 4).stroke(CF.yellow, lineWidth: 1)
            case .corner:
                RoundedRectangle(cornerRadius: 6).fill(CF.blueAct.opacity(0.85))
            }

            if showLabels && w > 26 {
                VStack(spacing: 2) {
                    if let sym = seg.symbol, w > 34 {
                        Image(systemName: sym)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(iconColor(seg.role))
                    }
                    if w > 44 {
                        Text(String(format: "%.0f", seg.widthCM))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(iconColor(seg.role))
                    }
                }
            }
        }
        .frame(width: w)
    }

    private func iconColor(_ role: WallSegment.Role) -> Color {
        switch role {
        case .base, .corner: return .white
        case .wall:          return CF.onAction
        case .appliance:     return CF.orange
        case .filler:        return Color(hex: "8A6D10")
        }
    }
}

// MARK: - UIKit bridges

/// Share-sheet wrapper (used for PDF export).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Document picker for importing a previously exported runs file.
struct JSONImporter: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText],
                                                    asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: JSONImporter
        init(_ parent: JSONImporter) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}

/// PHPicker-based photo picker — needs no photo-library permission (iOS 14+).
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.parent.onPick(image) }
                }
            }
        }
    }
}

// MARK: - Image data helpers

extension UIImage {
    func cfCompressed(maxDimension: CGFloat = 1200) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let img = renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
        return img.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Keyboard dismissal

extension View {
    func cfDismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - Toast / confirmation overlay

struct ConfirmToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.white)
            Text(text).font(.cfHead(14)).foregroundColor(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Capsule().fill(CF.ok))
        .shadow(color: CF.ok.opacity(0.4), radius: 10, y: 5)
    }
}
