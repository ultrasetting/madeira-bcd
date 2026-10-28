import Foundation

/// One game on Couch mode's shelves: a Steam game (installed or only owned) or a
/// game added to Madeira's library. Couch mode's views take these values and
/// never read Madeira's models themselves, so they also run in the Simulator
/// preview app (app/CouchPreview) without the engine.
struct CouchGame: Identifiable, Hashable {
    enum Source: Hashable {
        case steam(appID: Int)
        case added(UUID)
    }
    enum State: Hashable {
        case installed
        case notInstalled
        /// Download progress, 0...1.
        case downloading(Double)
    }

    var id: String
    var source: Source
    var title: String
    /// Portrait cover (Steam's library_600x900).
    var cover: URL?
    /// Wide backdrop (Steam's library_hero).
    var hero: URL?
    /// Transparent title logo drawn over the hero (Steam's logo.png).
    var logo: URL?
    var state: State
    var lastPlayed: Date?
    var minutesPlayed = 0
    var sizeBytes: Int64?
    var cloudSaves = false

    var isSteam: Bool {
        if case .steam = source { return true }
        return false
    }

    /// A Steam game with its artwork from Steam's CDN, as SteamCatalog loads it.
    static func steam(_ appID: Int, _ title: String, state: State, lastPlayed: Date? = nil,
                      minutesPlayed: Int = 0, sizeBytes: Int64? = nil, cloudSaves: Bool = true) -> CouchGame {
        let art = { (name: String) in URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/\(name)") }
        return CouchGame(id: "steam-\(appID)", source: .steam(appID: appID), title: title,
                         cover: art("library_600x900.jpg"), hero: art("library_hero.jpg"), logo: art("logo.png"),
                         state: state, lastPlayed: lastPlayed, minutesPlayed: minutesPlayed,
                         sizeBytes: sizeBytes, cloudSaves: cloudSaves)
    }

    /// "14 hrs played", as SteamPlaytime.played words it; nil when never played.
    var playtimeText: String? {
        guard minutesPlayed > 0 else { return nil }
        if minutesPlayed < 60 { return "\(minutesPlayed) min played" }
        let hours = Double(minutesPlayed) / 60
        return hours < 10 ? String(format: "%.1f hrs played", hours) : "\(Int(hours.rounded())) hrs played"
    }

    var lastPlayedText: String? {
        guard let lastPlayed else { return nil }
        if Date().timeIntervalSince(lastPlayed) < 60 * 60 { return "Played just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last played " + formatter.localizedString(for: lastPlayed, relativeTo: Date())
    }

    var sizeText: String? {
        sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }
}

/// One horizontal row of covers on the home screen.
struct CouchShelf: Identifiable, Hashable {
    var id: String
    var title: String
    var games: [CouchGame]

    /// The home screen's rows: recently played first, then installed Steam
    /// games, the rest of the Steam library, and the games added by hand.
    /// Empty rows are left out.
    static func make(from games: [CouchGame]) -> [CouchShelf] {
        let byTitle: (CouchGame, CouchGame) -> Bool = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let recent = games.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        let steam = games.filter(\.isSteam)
        let rows = [
            CouchShelf(id: "recent", title: "Continue playing", games: Array(recent.prefix(12))),
            CouchShelf(id: "installed", title: "Installed", games: steam.filter { $0.state != .notInstalled }.sorted(by: byTitle)),
            CouchShelf(id: "library", title: "Library", games: steam.filter { $0.state == .notInstalled }.sorted(by: byTitle)),
            CouchShelf(id: "added", title: "Other games", games: games.filter { !$0.isSteam }.sorted(by: byTitle)),
        ]
        return rows.filter { !$0.games.isEmpty }
    }
}

/// What the top bar shows besides the clock.
struct CouchStatus: Equatable {
    var jitReady = false
    var controllerConnected = false
}
