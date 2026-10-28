import Combine
import SwiftUI

// Couch mode inside Madeira: the shared views of CouchMode/ fed with the
// library's games, Steam's installs, downloads and playtime, player 1's pad
// (LibraryController) and the app's own launch path. This folder is the only
// part of Couch mode that knows Madeira's models; app/CouchPreview leaves it out.

/// Couch mode is on: the library shows as Couch mode until the guide's
/// Madeira library (or Settings › Appearance) turns it off. Applies at once.
enum CouchModeSetting {
    static let key = "madeiraCouchMode"
}

/// Shows Couch mode or Madeira's own library, following CouchModeSetting.
/// ContentView wraps LibraryView in it.
struct CouchModeSwitch<Library: View>: View {
    var play: (LibraryEntry) -> Void
    var enableJIT: () -> Void
    @ViewBuilder var library: () -> Library
    @AppStorage(CouchModeSetting.key) private var couch = false

    var body: some View {
        if couch {
            CouchModeHost(play: play, enableJIT: enableJIT, leave: { couch = false })
        } else {
            library()
        }
    }
}

/// Settings › Appearance's switch into Couch mode (LibraryView's Settings tab).
struct CouchModeSettingsSection: View {
    @AppStorage(CouchModeSetting.key) private var couch = false

    var body: some View {
        Section {
            Toggle("Couch mode", isOn: $couch)
        } footer: {
            Text("A full-screen library for playing with a controller, like Big Picture. Leave it from its menu (Start) › Madeira library.")
        }
    }
}

struct CouchModeHost: View {
    var play: (LibraryEntry) -> Void
    var enableJIT: () -> Void
    var leave: () -> Void
    @ObservedObject private var library = LibraryModel.shared
    @ObservedObject private var installs = SteamGamesModel.shared
    @ObservedObject private var steam = SteamOwnedLibrary.shared
    @ObservedObject private var cloud = SteamCloudSetting.shared
    @ObservedObject private var jit = LibraryJITState.shared
    @ObservedObject private var controller = LibraryController.shared
    // First-run setup, and Madeira Dock's client page (OnboardingModel), shown over
    // Couch mode as LibraryView shows them over the library.
    @ObservedObject private var onboarding = OnboardingModel.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var details: LibraryEntry?
    @State private var keys = PassthroughSubject<CouchCommand, Never>()
    @FocusState private var keyboardFocus: Bool

    /// Player 1's pad, as LibraryController names its buttons, and a hardware
    /// keyboard (arrows, Return, Escape, Tab), which Madeira's library has no
    /// commands for. Nothing reaches Couch mode while Game details is open over it.
    private var commands: AnyPublisher<CouchCommand, Never> {
        let covered = details != nil
        return LibraryController.shared.commands
            .compactMap { CouchCommand(rawValue: $0) }
            .merge(with: keys)
            .filter { _ in !covered }
            .eraseToAnyPublisher()
    }

    var body: some View {
        CouchHomeView(shelves: CouchShelf.make(from: games), commands: commands,
                      status: CouchStatus(jitReady: jit.enabled, controllerConnected: controller.connected),
                      play: start, install: install, properties: properties, guideAction: guide)
            .overlay(alignment: .top) { banner }
            .toolbar(.hidden, for: .navigationBar)
            .focusable()
            .focusEffectDisabled()
            .focused($keyboardFocus)
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard let command = Self.command(for: press) else { return .ignored }
                keys.send(command)
                return .handled
            }
            .onAppear {
                keyboardFocus = true
                refresh()
                CouchOrientation.hold(landscape: true)
                onboarding.presentIfNeeded()
            }
            // Leaving for the library, or a game session taking over.
            .onDisappear { CouchOrientation.hold(landscape: false) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .onChange(of: library.current) { _, current in if current != nil { details = nil } }
            .fullScreenCover(isPresented: $onboarding.presented) { OnboardingView() }
            .sheet(item: $details) { entry in
                LibraryDetail(entry: entry, play: { profile in
                    details = nil
                    play(profile)
                })
            }
    }

    // MARK: - Games

    /// Steam's games (owned, installed or downloading) and the games added to
    /// the library, as Couch mode's shelves take them.
    private var games: [CouchGame] {
        let owned = SteamOwnedLibrary.enabled ? steam.owned : []
        let steamGames = SteamGamesRules.items(installed: installs.games, owned: owned, search: "").map(steamGame)
        let added = library.entries.filter { $0.desktop != true && $0.steamAppID == nil }.map(addedGame)
        return steamGames + added
    }

    private func steamGame(_ item: SteamGamesRules.Item) -> CouchGame {
        let entry = library.entries.first { $0.steamAppID == item.id }
        let playtime = steam.playtime[item.id]
        let state: CouchGame.State
        if let download = steam.downloads[item.id] {
            switch download.state {
            case .failed: state = .notInstalled
            default: state = .downloading(download.progress.fraction)
            }
        } else {
            state = item.installed?.installed == true ? .installed : .notInstalled
        }
        let steamPlayed = playtime.flatMap { $0.lastPlayed > 0 ? Date(timeIntervalSince1970: TimeInterval($0.lastPlayed)) : nil }
        return .steam(item.id, item.name, state: state,
                      lastPlayed: [entry?.lastPlayed, steamPlayed].compactMap { $0 }.max(),
                      minutesPlayed: playtime?.minutes ?? 0, sizeBytes: entry?.folderBytes, cloudSaves: cloud.on)
    }

    private func addedGame(_ entry: LibraryEntry) -> CouchGame {
        let cover = entry.coverFile.map { LibraryModel.documents.appendingPathComponent("madeira-art/\($0)") }
        return CouchGame(id: entry.id.uuidString, source: .added(entry.id), title: entry.title,
                         cover: cover ?? entry.steamID.flatMap(SteamCatalog.cover),
                         hero: entry.steamID.flatMap(SteamCatalog.hero),
                         logo: entry.steamID.flatMap { URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\($0)/logo.png") },
                         state: .installed, lastPlayed: entry.lastPlayed, sizeBytes: entry.folderBytes)
    }

    /// The library entry a game starts with: its own, or for a Steam game the
    /// one LibraryModel keeps its settings in (made on first start).
    private func entry(for game: CouchGame) -> LibraryEntry? {
        switch game.source {
        case .added(let id):
            return library.entries.first { $0.id == id }
        case .steam(let appID):
            guard let installed = installs.games.first(where: { $0.id == appID && $0.installed }) else { return nil }
            return library.steamEntry(installed, title: game.title)
        }
    }

    // MARK: - Actions

    private func start(_ game: CouchGame) {
        // A Steam game starts through Madeira Dock, which needs Valve's client
        // components: open their download page rather than fail with an error.
        if game.isSteam, MadeiraDock.enabled, !MadeiraDock.clientInstalled {
            onboarding.offerDockClient()
            return
        }
        guard let entry = entry(for: game) else {
            library.error = "\(game.title) isn't installed yet."
            return
        }
        play(entry)
    }

    private func install(_ game: CouchGame) {
        guard case .steam(let appID) = game.source else { return }
        steam.install(appID)
    }

    private func properties(_ game: CouchGame) {
        guard let entry = entry(for: game) else {
            library.error = "Properties are available once \(game.title) is installed."
            return
        }
        details = entry
    }

    private func guide(_ item: CouchGuideItem) {
        switch item {
        case .home: break
        case .jit: if !jit.enabled { enableJIT() }
        case .library, .settings, .exit: leave()
        }
    }

    /// Reads Steam's install records and the account's library again, as the
    /// library's Steam section does when it appears.
    private func refresh() {
        installs.refresh()
        if SteamOwnedLibrary.enabled { steam.start(); steam.reconcileSession() }
    }

    // MARK: - Messages

    /// What the library would show as an alert, as a banner: JIT being enabled
    /// for Play, then errors and notices. A tap dismisses it.
    @ViewBuilder private var banner: some View {
        if let text = message {
            Button(action: dismissMessage) {
                Label(text, systemImage: library.startingJIT != nil ? "bolt.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.top, 10)
            .padding(.horizontal, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.2), value: text)
        }
    }

    private var message: String? {
        if library.startingJIT != nil { return "Enabling JIT, then starting the game…" }
        return library.error ?? library.jitNotice ?? library.restartNotice ?? steam.error
    }

    private func dismissMessage() {
        if library.error != nil { library.error = nil }
        else if library.jitNotice != nil { library.jitNotice = nil }
        else if library.restartNotice != nil { library.restartNotice = nil }
        else { steam.error = nil }
    }

    private static func command(for press: KeyPress) -> CouchCommand? {
        switch press.key {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .return, .space: return .accept
        case .escape, .delete: return .back
        case .tab: return .menu
        default: return nil
        }
    }
}
