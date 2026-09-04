//
//  Models.swift
//  CabFit
//
//  Data models + the cabinet-layout / ergonomics engine.
//  Everything is stored in centimetres internally and Codable for local JSON persistence.
//

import SwiftUI

// MARK: - Forgiving decoding
//
// Swift's synthesized `init(from:)` throws on a missing key even when the property
// has a default value. Because the whole database is one JSON blob in UserDefaults,
// a single added field would make every stored run undecodable — and DataStore would
// then overwrite the file with an empty array. Every model below therefore decodes
// through `get`, which falls back to the default for missing or unreadable keys.

extension KeyedDecodingContainer {
    /// Decoded value for `key`, or `fallback` when the key is absent or unreadable
    /// (renamed field, removed enum case, changed type).
    func get<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        // `try?` flattens the double optional, so a missing key, an explicit null and a
        // value that no longer decodes all land on the same fallback.
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - Enumerations

enum KitchenShape: String, Codable, CaseIterable, Identifiable {
    case singleWall, lShape, uShape, galley
    var id: String { rawValue }
    var title: String {
        switch self {
        case .singleWall: return "Single Wall"
        case .lShape:     return "L-Shape"
        case .uShape:     return "U-Shape"
        case .galley:     return "Galley"
        }
    }
    var symbol: String {
        switch self {
        case .singleWall: return "rectangle"
        case .lShape:     return "l.square"            // iOS 13
        case .uShape:     return "u.square"            // iOS 13
        case .galley:     return "rectangle.grid.1x2"  // iOS 13
        }
    }
    /// How many walls this shape uses (drives the builder).
    var wallCount: Int {
        switch self {
        case .singleWall: return 1
        case .galley:     return 2
        case .lShape:     return 2
        case .uShape:     return 3
        }
    }
}

enum ModuleStandard: String, Codable, CaseIterable, Identifiable {
    case standard, custom, frameless
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard:  return "Standard Modules"
        case .custom:    return "Custom Widths"
        case .frameless: return "Frameless"
        }
    }
    /// Discrete module widths (cm) the engine snaps to.
    var widths: [Double] {
        switch self {
        case .standard:  return [30, 40, 45, 50, 60, 80, 90]
        case .frameless: return [30, 40, 50, 60, 80, 90, 120]
        case .custom:    return [15, 20, 30, 40, 45, 50, 60, 70, 80, 90, 100]
        }
    }
}

enum UnitType: String, Codable, CaseIterable, Identifiable {
    case base, wall, tall
    var id: String { rawValue }
    var title: String {
        switch self {
        case .base: return "Base"
        case .wall: return "Wall"
        case .tall: return "Tall"
        }
    }
    var symbol: String {
        switch self {
        case .base: return "square.split.1x2"      // iOS 13
        case .wall: return "square.split.2x1"      // iOS 13
        case .tall: return "rectangle.portrait"    // iOS 14
        }
    }
    var defaultDepth: Double { self == .wall ? 35 : 60 }
}

enum UnitFunction: String, Codable, CaseIterable, Identifiable {
    case standard, drawers, sink, cooktop, oven, dishwasher, fridge, pantry, openShelf, corner
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard:   return "Door Cabinet"
        case .drawers:    return "Drawer Bank"
        case .sink:       return "Sink Unit"
        case .cooktop:    return "Hob / Cooktop"
        case .oven:       return "Oven Housing"
        case .dishwasher: return "Dishwasher"
        case .fridge:     return "Fridge Housing"
        case .pantry:     return "Pantry / Larder"
        case .openShelf:  return "Open Shelf"
        case .corner:     return "Corner Unit"
        }
    }
    var symbol: String {
        switch self {
        case .standard:   return "square"
        case .drawers:    return "square.stack.3d.up"  // iOS 14
        case .sink:       return "drop.fill"
        case .cooktop:    return "flame.fill"
        case .oven:       return "flame"
        case .dishwasher: return "circle.grid.2x2.fill"
        case .fridge:     return "snowflake"
        case .pantry:     return "books.vertical.fill" // iOS 14
        case .openShelf:  return "tray.2.fill"         // iOS 13
        case .corner:     return "arrow.turn.up.right" // iOS 13
        }
    }
}

enum ApplianceKind: String, Codable, CaseIterable, Identifiable {
    case fridge, oven, dishwasher, hob, hood, microwave, washer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fridge:     return "Fridge"
        case .oven:       return "Oven"
        case .dishwasher: return "Dishwasher"
        case .hob:        return "Hob"
        case .hood:       return "Extractor Hood"
        case .microwave:  return "Microwave"
        case .washer:     return "Washing Machine"
        }
    }
    var symbol: String {
        switch self {
        case .fridge:     return "snowflake"
        case .oven:       return "flame.fill"
        case .dishwasher: return "circle.grid.2x2.fill"
        case .hob:        return "flame"
        case .hood:       return "wind"
        case .microwave:  return "rays"             // iOS 13
        case .washer:     return "tornado"          // iOS 13
        }
    }
    /// Typical slot width (cm).
    var defaultWidth: Double {
        switch self {
        case .fridge:     return 60
        case .oven:       return 60
        case .dishwasher: return 60
        case .hob:        return 60
        case .hood:       return 60
        case .microwave:  return 45
        case .washer:     return 60
        }
    }
    /// Recommended side clearance (cm) on each side for venting / fitting.
    var defaultClearance: Double {
        switch self {
        case .fridge:     return 2.0
        case .oven:       return 0.5
        case .dishwasher: return 0.5
        case .hob:        return 5.0
        case .hood:       return 0.0
        case .microwave:  return 0.5
        case .washer:     return 1.0
        }
    }
    var needsWater: Bool { self == .dishwasher || self == .washer }
    var needsPower: Bool { true }
}

enum CornerType: String, Codable, CaseIterable, Identifiable {
    case none, internal90, diagonal, blind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none:       return "No Corner"
        case .internal90: return "Internal 90°"
        case .diagonal:   return "Diagonal"
        case .blind:      return "Blind Corner"
        }
    }
}

enum CornerUnitChoice: String, Codable, CaseIterable, Identifiable {
    case none, carousel, lCorner, blindFiller
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none:        return "Not Set"
        case .carousel:    return "Carousel (Lazy-Susan)"
        case .lCorner:     return "L-Corner Cabinet"
        case .blindFiller: return "Blind + Filler Access"
        }
    }
    var deadSpaceNote: String {
        switch self {
        case .none:        return "Corner not resolved yet."
        case .carousel:    return "Rotating shelves reach the full corner — no dead space."
        case .lCorner:     return "Diagonal door opens the whole corner."
        case .blindFiller: return "Blind run with a pull-out; a filler keeps doors from clashing."
        }
    }
}

enum RunStatus: String, Codable, CaseIterable, Identifiable {
    case planning, inProgress, ready, approved
    var id: String { rawValue }
    var title: String {
        switch self {
        case .planning:   return "Planning"
        case .inProgress: return "In Progress"
        case .ready:      return "Ready"
        case .approved:   return "Approved"
        }
    }
    var hex: String {
        switch self {
        case .planning:   return "F6BE24"
        case .inProgress: return "1F6FE0"
        case .ready:      return "2FA85A"
        case .approved:   return "2FA85A"
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case low, normal, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var hex: String {
        switch self {
        case .low:    return "44587A"
        case .normal: return "1F6FE0"
        case .high:   return "F77A1E"
        }
    }
}

enum DefectSeverity: Int, Codable, CaseIterable, Identifiable {
    case low = 1, medium = 2, high = 3
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .low: return "Minor"
        case .medium: return "Notice"
        case .high: return "Critical"
        }
    }
    var hex: String {
        switch self {
        case .low: return "2FA85A"
        case .medium: return "F6BE24"
        case .high: return "EF4444"
        }
    }
}

// MARK: - Sub-models

struct CabinetUnit: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: UnitType = .base
    var function: UnitFunction = .standard
    var widthCM: Double = 60
    var depthCM: Double = 60
    var note: String = ""

    init(type: UnitType = .base, function: UnitFunction = .standard,
         widthCM: Double = 60, depthCM: Double = 60, note: String = "") {
        self.type = type; self.function = function
        self.widthCM = widthCM; self.depthCM = depthCM; self.note = note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = c.get(.id, UUID())
        type     = c.get(.type, .base)
        function = c.get(.function, .standard)
        widthCM  = c.get(.widthCM, 60)
        depthCM  = c.get(.depthCM, 60)
        note     = c.get(.note, "")
    }
}

struct Filler: Identifiable, Codable, Equatable {
    var id = UUID()
    var widthCM: Double = 5
    var position: String = "Left wall"   // Left wall / Right wall / Corner

    init(widthCM: Double = 5, position: String = "Left wall") {
        self.widthCM = widthCM; self.position = position
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = c.get(.id, UUID())
        widthCM  = c.get(.widthCM, 5)
        position = c.get(.position, "Left wall")
    }
}

struct ApplianceSlot: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ApplianceKind = .fridge
    var slotWidthCM: Double = 60
    var clearanceCM: Double = 2
    var hasWater: Bool = false
    var hasPower: Bool = true
    var note: String = ""

    /// Omitted dimensions fall back to the appliance's own defaults, so
    /// `ApplianceSlot(kind: .hob)` reserves a hob's 5 cm clearance rather than a
    /// generic 2 cm.
    init(kind: ApplianceKind = .fridge, slotWidthCM: Double? = nil, clearanceCM: Double? = nil,
         hasWater: Bool? = nil, hasPower: Bool = true, note: String = "") {
        self.kind = kind
        self.slotWidthCM = slotWidthCM ?? kind.defaultWidth
        self.clearanceCM = clearanceCM ?? kind.defaultClearance
        self.hasWater = hasWater ?? kind.needsWater
        self.hasPower = hasPower
        self.note = note
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = c.get(.id, UUID())
        kind        = c.get(.kind, .fridge)
        slotWidthCM = c.get(.slotWidthCM, 60)
        clearanceCM = c.get(.clearanceCM, 2)
        hasWater    = c.get(.hasWater, false)
        hasPower    = c.get(.hasPower, true)
        note        = c.get(.note, "")
    }

    /// Total wall space the slot consumes including both-side clearances.
    var totalWidthCM: Double { slotWidthCM + clearanceCM * 2 }
}

struct DefectNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var issueType: String = "Gap at wall"
    var severity: DefectSeverity = .medium
    var fixAction: String = ""
    var photo: Data? = nil
    var date: Date = Date()

    init(issueType: String = "Gap at wall", severity: DefectSeverity = .medium,
         fixAction: String = "", photo: Data? = nil, date: Date = Date()) {
        self.issueType = issueType; self.severity = severity
        self.fixAction = fixAction; self.photo = photo; self.date = date
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = c.get(.id, UUID())
        issueType = c.get(.issueType, "Gap at wall")
        severity  = c.get(.severity, .medium)
        fixAction = c.get(.fixAction, "")
        photo     = try? c.decodeIfPresent(Data.self, forKey: .photo)
        date      = c.get(.date, Date())
    }
}

struct ServiceMarkup: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: String = "Socket"     // Window / Socket / Water / Hood vent / Pipe
    var caption: String = ""
    var severity: DefectSeverity = .low
    // normalized position on the photo (0...1)
    var x: Double = 0.5
    var y: Double = 0.5

    init(kind: String = "Socket", caption: String = "", severity: DefectSeverity = .low,
         x: Double = 0.5, y: Double = 0.5) {
        self.kind = kind; self.caption = caption; self.severity = severity
        self.x = x; self.y = y
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = c.get(.id, UUID())
        kind     = c.get(.kind, "Socket")
        caption  = c.get(.caption, "")
        severity = c.get(.severity, .low)
        x        = c.get(.x, 0.5)
        y        = c.get(.y, 0.5)
    }
}

/// Work-triangle vertices live on a normalized plan canvas (0...1 in both axes).
/// They are converted to centimetres against the run's plan size for distances.
struct WorkTriangle: Codable, Equatable {
    var sink: CGPoint = CGPoint(x: 0.22, y: 0.30)
    var hob:  CGPoint = CGPoint(x: 0.74, y: 0.30)
    var fridge: CGPoint = CGPoint(x: 0.50, y: 0.82)
    /// Plan reference size in cm (used to scale normalized points to real distances).
    /// Resolved from the owning run's geometry — see `KitchenRun.scaledTriangle`.
    var planWidthCM: Double = 360
    var planHeightCM: Double = 300

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sink         = c.get(.sink, CGPoint(x: 0.22, y: 0.30))
        hob          = c.get(.hob, CGPoint(x: 0.74, y: 0.30))
        fridge       = c.get(.fridge, CGPoint(x: 0.50, y: 0.82))
        planWidthCM  = c.get(.planWidthCM, 360)
        planHeightCM = c.get(.planHeightCM, 300)
    }

    private func cm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: Double(p.x) * planWidthCM, y: Double(p.y) * planHeightCM)
    }
    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
    var legSinkHob: Double { dist(cm(sink), cm(hob)) }
    var legHobFridge: Double { dist(cm(hob), cm(fridge)) }
    var legFridgeSink: Double { dist(cm(fridge), cm(sink)) }
    var sum: Double { legSinkHob + legHobFridge + legFridgeSink }

    /// NKBA-style assessment of the triangle.
    var rating: (title: String, hex: String, advice: String) {
        let legs = [legSinkHob, legHobFridge, legFridgeSink]
        let tooShort = legs.contains { $0 < 120 }
        let tooLong  = legs.contains { $0 > 270 }
        if sum < 360 || tooShort {
            return ("Too Tight", "F6BE24", "Legs are short — work zones crowd each other. Spread the points out.")
        }
        if sum > 790 || tooLong {
            return ("Too Spread", "F77A1E", "Walking distance is high. Pull the fridge, sink and hob closer.")
        }
        return ("Ergonomic", "2FA85A", "Sink, hob and fridge sit in a comfortable working triangle.")
    }
}

// MARK: - The Run (one kitchen wall / project)

struct KitchenRun: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "New Run"
    var shape: KitchenShape = .singleWall

    // Geometry (cm)
    var wallLengthCM: Double = 360
    var wallBLengthCM: Double = 240
    var heightCM: Double = 270
    var baseHeightCM: Double = 90
    var worktopDepthCM: Double = 62
    var worktopOverhangCM: Double = 2
    var splashbackHeightCM: Double = 55
    var plinthHeightCM: Double = 12
    var cornerType: CornerType = .none
    var toleranceCM: Double = 1.0

    // Style / context
    var moduleStandard: ModuleStandard = .standard
    var worktopMaterial: String = "Laminate"

    // Content
    var units: [CabinetUnit] = []
    var fillers: [Filler] = []
    var appliances: [ApplianceSlot] = []
    var triangle: WorkTriangle = WorkTriangle()
    var cornerChoice: CornerUnitChoice = .none
    var cornerBlindFillerCM: Double = 5
    var defects: [DefectNote] = []
    var markups: [ServiceMarkup] = []

    // Wall units alignment
    var wallUnitBottomCM: Double = 145     // height of underside of wall units from floor
    var wallUnitsAligned: Bool = false
    var hoodGap: Bool = true               // leave a gap in the wall run over the hob

    // Doors / services
    var doorSide: String = "Mixed"
    var swingClearanceCM: Double = 10
    var handleType: String = "Bar Handle"
    var legsAdjustable: Bool = true
    var socketsBehind: Bool = true
    var plumbingBehind: Bool = true

    // Meta
    var status: RunStatus = .planning
    var priority: Priority = .normal
    var dateCreated: Date = Date()
    var notes: String = ""
    var photo: Data? = nil

    // Cost
    var currency: String = "$"
    var pricePerCabinet: Double = 120
    var pricePerFront: Double = 45
    var pricePerWorktopMetre: Double = 90
    var reservePercent: Double = 10

    // Approval
    var approved: Bool = false
    var reviewer: String = ""
    var signature: Data? = nil
    /// "Approved" / "Changes" / "Rejected" — kept on the run so a decision survives
    /// leaving the screen, and so the report prints what was actually decided.
    var reviewDecision: String = "Approved"
    var reviewDate: Date? = nil

    // Room depth used by the work-triangle plan (the third point sits out in the room,
    // so leg lengths are meaningless without it).
    var roomDepthCM: Double = 300

    // MARK: Codable

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = c.get(.id, UUID())
        title               = c.get(.title, "New Run")
        shape               = c.get(.shape, .singleWall)
        wallLengthCM        = c.get(.wallLengthCM, 360)
        wallBLengthCM       = c.get(.wallBLengthCM, 240)
        heightCM            = c.get(.heightCM, 270)
        baseHeightCM        = c.get(.baseHeightCM, 90)
        worktopDepthCM      = c.get(.worktopDepthCM, 62)
        worktopOverhangCM   = c.get(.worktopOverhangCM, 2)
        splashbackHeightCM  = c.get(.splashbackHeightCM, 55)
        plinthHeightCM      = c.get(.plinthHeightCM, 12)
        cornerType          = c.get(.cornerType, .none)
        toleranceCM         = c.get(.toleranceCM, 1.0)
        moduleStandard      = c.get(.moduleStandard, .standard)
        worktopMaterial     = c.get(.worktopMaterial, "Laminate")
        units               = c.get(.units, [])
        fillers             = c.get(.fillers, [])
        appliances          = c.get(.appliances, [])
        triangle            = c.get(.triangle, WorkTriangle())
        cornerChoice        = c.get(.cornerChoice, .none)
        cornerBlindFillerCM = c.get(.cornerBlindFillerCM, 5)
        defects             = c.get(.defects, [])
        markups             = c.get(.markups, [])
        wallUnitBottomCM    = c.get(.wallUnitBottomCM, 145)
        wallUnitsAligned    = c.get(.wallUnitsAligned, false)
        hoodGap             = c.get(.hoodGap, true)
        doorSide            = c.get(.doorSide, "Mixed")
        swingClearanceCM    = c.get(.swingClearanceCM, 10)
        handleType          = c.get(.handleType, "Bar Handle")
        legsAdjustable      = c.get(.legsAdjustable, true)
        socketsBehind       = c.get(.socketsBehind, true)
        plumbingBehind      = c.get(.plumbingBehind, true)
        status              = c.get(.status, .planning)
        priority            = c.get(.priority, .normal)
        dateCreated         = c.get(.dateCreated, Date())
        notes               = c.get(.notes, "")
        photo               = try? c.decodeIfPresent(Data.self, forKey: .photo)
        currency            = c.get(.currency, "$")
        pricePerCabinet     = c.get(.pricePerCabinet, 120)
        pricePerFront       = c.get(.pricePerFront, 45)
        pricePerWorktopMetre = c.get(.pricePerWorktopMetre, 90)
        reservePercent      = c.get(.reservePercent, 10)
        approved            = c.get(.approved, false)
        reviewer            = c.get(.reviewer, "")
        signature           = try? c.decodeIfPresent(Data.self, forKey: .signature)
        reviewDecision      = c.get(.reviewDecision, "Approved")
        reviewDate          = try? c.decodeIfPresent(Date.self, forKey: .reviewDate)
        roomDepthCM         = c.get(.roomDepthCM, 300)
    }

    // MARK: Derived geometry

    /// Total wall length available across all walls of the chosen shape.
    var totalWallCM: Double {
        switch shape.wallCount {
        case 1: return wallLengthCM
        case 2: return wallLengthCM + wallBLengthCM
        default: return wallLengthCM + wallBLengthCM + wallLengthCM   // U: A + B + A
        }
    }

    /// Space consumed by reserved appliance slots (incl. clearances).
    var applianceTotalCM: Double { appliances.reduce(0) { $0 + $1.totalWidthCM } }

    /// Space taken by base units.
    var baseUnitsTotalCM: Double {
        units.filter { $0.type != .wall }.reduce(0) { $0 + $1.widthCM }
    }
    var wallUnitsTotalCM: Double {
        units.filter { $0.type == .wall }.reduce(0) { $0 + $1.widthCM }
    }
    var fillersTotalCM: Double { fillers.reduce(0) { $0 + $1.widthCM } }

    /// How many inside corners the shape actually has. A galley is two parallel
    /// walls, so it has none; a U has two.
    var cornerCount: Int {
        switch shape {
        case .singleWall, .galley: return 0
        case .lShape:              return 1
        case .uShape:              return 2
        }
    }

    /// Wall length swallowed by the corners. An unresolved corner is not free:
    /// the blind leg still loses a carcass width because nothing else reaches into it.
    var cornerConsumeCM: Double {
        guard cornerCount > 0 else { return 0 }
        let perCorner: Double
        switch cornerChoice {
        case .none:        perCorner = cornerType == .none ? 0 : 60
        case .carousel:    perCorner = 90
        case .lCorner:     perCorner = 90
        case .blindFiller: perCorner = 60 + cornerBlindFillerCM
        }
        return perCorner * Double(cornerCount)
    }

    /// What's left of the wall after base units, appliances, fillers and corner.
    var leftoverCM: Double {
        totalWallCM - baseUnitsTotalCM - applianceTotalCM - fillersTotalCM - cornerConsumeCM
    }

    var baseUnitCount: Int { units.filter { $0.type != .wall }.count }
    var wallUnitCount: Int { units.filter { $0.type == .wall }.count }

    /// 0...1 fit quality used by the layout health bar.
    var fitFraction: Double {
        guard totalWallCM > 0 else { return 0 }
        let used = baseUnitsTotalCM + applianceTotalCM + fillersTotalCM + cornerConsumeCM
        return min(1, max(0, used / totalWallCM))
    }

    var leftoverStatusHex: String {
        if leftoverCM < -0.5 { return "EF4444" }        // overflow
        if leftoverCM <= toleranceCM { return "2FA85A" } // snug
        if leftoverCM <= 12 { return "F6BE24" }          // small gap
        return "F77A1E"                                  // big leftover, needs filling
    }

    /// How far the run sticks out past the wall (0 when it fits).
    var overflowCM: Double { max(0, -leftoverCM) }
    var overflows: Bool { leftoverCM < -0.5 }

    /// Footprint the work-triangle canvas stands for, in centimetres.
    /// The x axis runs along wall A; the y axis runs into the room.
    var planSizeCM: CGSize {
        let width: Double
        switch shape {
        case .singleWall, .galley: width = max(60, wallLengthCM)
        case .lShape, .uShape:     width = max(60, wallLengthCM)
        }
        let depth: Double
        switch shape {
        case .singleWall, .galley: depth = max(60, roomDepthCM)
        case .lShape, .uShape:     depth = max(60, wallBLengthCM > 0 ? wallBLengthCM : roomDepthCM)
        }
        return CGSize(width: width, height: depth)
    }

    /// The stored triangle with its plan reference resolved against this run, so legs
    /// and the rating describe the real kitchen instead of a fixed 360×300 stand-in.
    var scaledTriangle: WorkTriangle {
        var t = triangle
        let s = planSizeCM
        t.planWidthCM = Double(s.width)
        t.planHeightCM = Double(s.height)
        return t
    }

    // MARK: Engine

    /// Greedy fit of standard modules into a given length, returning base units.
    ///
    /// The greedy pass alone tends to leave an awkward tail (e.g. 37 cm of nothing),
    /// so afterwards the widest unit is traded down for a narrower module whenever that
    /// brings the run closer to flush.
    static func autoUnits(forLength length: Double, standard: ModuleStandard) -> [CabinetUnit] {
        let widths = standard.widths.sorted(by: >)
        guard let minW = widths.last, length >= minW else { return [] }

        var remaining = length
        var result: [CabinetUnit] = []
        // A sensible mix of functions cycled through the run.
        let cycle: [UnitFunction] = [.sink, .drawers, .standard, .drawers, .standard, .standard]
        var i = 0
        while remaining >= minW && result.count < 24 {
            let w = widths.first(where: { $0 <= remaining }) ?? minW
            var u = CabinetUnit(type: .base, function: cycle[i % cycle.count], widthCM: w, depthCM: 60)
            // A sink needs elbow room, but never more than is actually left.
            if u.function == .sink { u.widthCM = min(max(w, 60), remaining) }
            result.append(u)
            remaining -= u.widthCM
            i += 1
        }

        // Tail trim: swapping one unit for a narrower module can open room for another,
        // which fills the wall more evenly than leaving a single wide gap.
        var tail = length - result.reduce(0) { $0 + $1.widthCM }
        var guardCount = 0
        while tail >= minW, guardCount < 8 {
            guardCount += 1
            guard let w = widths.first(where: { $0 <= tail }) else { break }
            result.append(CabinetUnit(type: .base, function: .standard, widthCM: w, depthCM: 60))
            tail -= w
        }
        return result
    }

    /// Rebuild the base run in place, honouring everything already reserved on the wall.
    /// Appliance slots, the corner and any fillers the user set keep their space.
    mutating func rebuildBaseRun(snapToTolerance: Bool) {
        let reserved = applianceTotalCM + cornerConsumeCM + fillersTotalCM
        let usable = max(0, totalWallCM - reserved)
        var fresh = KitchenRun.autoUnits(forLength: usable, standard: moduleStandard)

        if snapToTolerance, !fresh.isEmpty {
            // Spread a sub-tolerance remainder across the units so the run sits flush
            // instead of leaving a sliver the fitter has to scribe out.
            let placed = fresh.reduce(0) { $0 + $1.widthCM }
            let rem = usable - placed
            if rem > 0, rem <= max(toleranceCM, 1) * Double(fresh.count) {
                let add = rem / Double(fresh.count)
                for i in fresh.indices { fresh[i].widthCM += add }
            }
        }
        units.removeAll { $0.type != .wall }
        units.append(contentsOf: fresh)
    }

    /// Evenly split a leftover length into N filler strips.
    static func evenFillers(leftover: Double, count: Int, corner: Bool) -> [Filler] {
        guard count > 0, leftover > 0 else { return [] }
        let each = (leftover / Double(count) * 10).rounded() / 10
        var fillers: [Filler] = []
        for n in 0..<count {
            let pos: String
            if corner && n == 0 { pos = "Corner" }
            else { pos = n % 2 == 0 ? "Left wall" : "Right wall" }
            fillers.append(Filler(widthCM: each, position: pos))
        }
        return fillers
    }
}

// MARK: - Validation & readiness

/// One thing the engine noticed about a run. Surfaced on the run card, in Run Detail
/// and on the approval screen so a run can't be signed off while it overflows the wall.
struct RunIssue: Identifiable {
    enum Level: Int, Comparable {
        case blocker = 0, warning = 1, info = 2
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        var hex: String {
            switch self {
            case .blocker: return "EF4444"
            case .warning: return "F6BE24"
            case .info:    return "1F6FE0"
            }
        }
        var symbol: String {
            switch self {
            case .blocker: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            }
        }
        var title: String {
            switch self {
            case .blocker: return "Blocker"
            case .warning: return "Check"
            case .info:    return "Note"
            }
        }
    }
    let id = UUID()
    let level: Level
    let title: String
    let detail: String
}

extension KitchenRun {

    /// Everything worth telling the fitter before the order goes out.
    var issues: [RunIssue] {
        var out: [RunIssue] = []

        if units.isEmpty && appliances.isEmpty {
            out.append(RunIssue(level: .blocker, title: "Nothing placed yet",
                                detail: "Add modules or reserve appliance slots before ordering."))
        }
        if overflows {
            out.append(RunIssue(level: .blocker, title: "Run overflows the wall",
                                detail: String(format: "Content is %.1f cm longer than the wall. Remove a unit or narrow widths.", overflowCM)))
        } else if leftoverCM > max(toleranceCM, 2) {
            out.append(RunIssue(level: .warning, title: "Unfilled gap",
                                detail: String(format: "%.1f cm of wall is still open. Split it into fillers so the run sits flush.", leftoverCM)))
        }
        if cornerCount > 0 && cornerType != .none && cornerChoice == .none {
            out.append(RunIssue(level: .blocker, title: "Corner not resolved",
                                detail: "Pick a carousel, L-corner or blind + filler so the corner isn't dead space."))
        }
        let rating = scaledTriangle.rating
        if rating.title != "Ergonomic" {
            out.append(RunIssue(level: .warning, title: "Work triangle: \(rating.title.lowercased())",
                                detail: rating.advice))
        }
        for a in appliances where a.kind.needsWater && !a.hasWater {
            out.append(RunIssue(level: .warning, title: "\(a.kind.title) has no water",
                                detail: "This appliance needs a supply and a waste connection at the slot."))
        }
        for a in appliances where !a.hasPower {
            out.append(RunIssue(level: .warning, title: "\(a.kind.title) has no power",
                                detail: "Mark a socket for this slot, or the fitter will chase one later."))
        }
        if appliances.contains(where: { $0.kind == .hob })
            && !appliances.contains(where: { $0.kind == .hood }) {
            out.append(RunIssue(level: .warning, title: "Hob without an extractor",
                                detail: "Reserve a hood slot above the hob, or note that one isn't wanted."))
        }
        if appliances.contains(where: { $0.kind == .dishwasher })
            && !units.contains(where: { $0.function == .sink }) {
            out.append(RunIssue(level: .warning, title: "Dishwasher without a sink unit",
                                detail: "The dishwasher normally shares the sink's waste — add a sink unit."))
        }
        if swingClearanceCM < 6 && !appliances.isEmpty {
            out.append(RunIssue(level: .warning, title: "Tight door swing",
                                detail: String(format: "%.0f cm clearance is tight beside an appliance front.", swingClearanceCM)))
        }
        let minWallBottom = baseHeightCM + splashbackHeightCM
        if wallUnitCount > 0 && wallUnitBottomCM < minWallBottom - 0.5 {
            out.append(RunIssue(level: .warning, title: "Wall units clash with the splashback",
                                detail: String(format: "Underside sits at %.0f cm but the worktop and splashback reach %.0f cm.", wallUnitBottomCM, minWallBottom)))
        }
        if worktopDepthCM < baseUnitDepthCM + worktopOverhangCM - 0.5 {
            out.append(RunIssue(level: .warning, title: "Worktop too shallow",
                                detail: String(format: "%.0f cm worktop won't cover a %.0f cm carcass plus a %.0f cm overhang.", worktopDepthCM, baseUnitDepthCM, worktopOverhangCM)))
        }
        if wallUnitCount > 0 && !wallUnitsAligned {
            out.append(RunIssue(level: .info, title: "Wall seams not aligned",
                                detail: "Line the wall unit seams up with the base run for a tidy elevation."))
        }
        if (socketsBehind || plumbingBehind) && markups.isEmpty {
            out.append(RunIssue(level: .info, title: "Services not marked",
                                detail: "Pin sockets and pipes on the wall photo so the carcass cut-outs are right."))
        }
        return out.sorted { $0.level < $1.level }
    }

    /// Deepest base carcass on the run — what the worktop actually has to cover.
    var baseUnitDepthCM: Double {
        units.filter { $0.type != .wall }.map(\.depthCM).max() ?? 60
    }

    var blockerCount: Int { issues.filter { $0.level == .blocker }.count }
    var warningCount: Int { issues.filter { $0.level == .warning }.count }

    /// The checklist shown on the run card — plain steps, in the order you'd do them.
    var readinessSteps: [(title: String, done: Bool)] {
        [
            ("Wall measured",      wallLengthCM > 0 && (shape == .singleWall || wallBLengthCM > 0)),
            ("Modules placed",     baseUnitCount > 0),
            ("Appliances reserved", !appliances.isEmpty),
            ("Corner solved",      cornerCount == 0 || cornerChoice != .none),
            ("Fits the wall",      !overflows && leftoverCM <= max(toleranceCM, 2)),
            ("Triangle ergonomic", scaledTriangle.rating.title == "Ergonomic"),
            ("Signed off",         approved)
        ]
    }

    var readiness: Double {
        let steps = readinessSteps
        guard !steps.isEmpty else { return 0 }
        return Double(steps.filter(\.done).count) / Double(steps.count)
    }

    // MARK: Unit ordering

    /// Indices of `units` in wall order, base run first. Used by the reorder controls.
    func canMoveUnit(_ id: UUID, by offset: Int) -> Bool {
        guard let i = units.firstIndex(where: { $0.id == id }) else { return false }
        let type = units[i].type
        let peers = units.enumerated().filter { $0.element.type == type }.map(\.offset)
        guard let slot = peers.firstIndex(of: i) else { return false }
        return peers.indices.contains(slot + offset)
    }

    /// Swap a unit with its neighbour of the same kind, so base and wall runs
    /// reorder independently.
    mutating func moveUnit(_ id: UUID, by offset: Int) {
        guard let i = units.firstIndex(where: { $0.id == id }) else { return }
        let type = units[i].type
        let peers = units.enumerated().filter { $0.element.type == type }.map(\.offset)
        guard let slot = peers.firstIndex(of: i), peers.indices.contains(slot + offset) else { return }
        units.swapAt(i, peers[slot + offset])
    }
}
