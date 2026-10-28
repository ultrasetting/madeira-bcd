import Combine
import SwiftUI

/// Couch mode: a full-screen, controller-first home in the spirit of Steam's Big
/// Picture. The focused game's hero art fills the screen behind shelves of
/// covers; A opens its page, Start the guide. It is driven by CouchCommand, so a
/// pad, a keyboard and touch all work, and it takes plain values and closures,
/// so app/CouchPreview runs it in the Simulator with mock games.
struct CouchHomeView: View {
    var shelves: [CouchShelf]
    var commands: AnyPublisher<CouchCommand, Never>
    var status: CouchStatus
    var play: (CouchGame) -> Void
    var install: (CouchGame) -> Void
    var properties: (CouchGame) -> Void = { _ in }
    var guideAction: (CouchGuideItem) -> Void = { _ in }

    @State private var focus = CouchFocus()
    @State private var pageID: String?
    @State private var pageButton = 0
    @State private var guideOpen = false
    @State private var guideIndex = 0

    private var focusedGame: CouchGame? { focus.game(in: shelves) }
    /// The open page's game, read again from the shelves so a download's
    /// progress shows as it moves.
    private var pageGame: CouchGame? {
        pageID.flatMap { id in shelves.lazy.flatMap(\.games).first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geo in
            let coverHeight = min(170, max(96, geo.size.height * 0.31))
            ZStack {
                CouchBackdrop(game: pageGame ?? focusedGame, deep: pageGame != nil)
                if let game = pageGame {
                    CouchGamePage(game: game, status: status, selection: pageButton,
                                  primary: { primary(game) }, properties: { properties(game) },
                                  close: { pageID = nil }, menu: openGuide,
                                  select: { pageButton = $0 })
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                } else {
                    home(coverHeight: coverHeight)
                        .transition(.opacity)
                }
                if guideOpen {
                    CouchGuide(selection: guideIndex, status: status,
                               activate: { activate(CouchGuideItem.allCases[$0]) },
                               close: { guideOpen = false })
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.22), value: pageID)
            .animation(.easeOut(duration: 0.2), value: guideOpen)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onReceive(commands) { handle($0) }
        .onChange(of: focus) { _, _ in prefetchNeighbours() }
        .onChange(of: shelves) { old, new in focus.keep(focus.game(in: old)?.id, in: new) }
        .onAppear { prefetchNeighbours() }
    }

    private func home(coverHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CouchTopBar(title: "Home", status: status)
            if shelves.isEmpty {
                CouchEmptyLibrary(openLibrary: { guideAction(.library) })
            } else {
                Spacer(minLength: 6)
                CouchGameInfo(game: focusedGame)
                Spacer(minLength: 10)
                shelfStack(coverHeight: coverHeight)
            }
            CouchHintBar(hints: shelves.isEmpty ? [
                CouchHint(glyph: "A", label: "Madeira library", action: { guideAction(.library) }),
                CouchHint(glyph: "line.3.horizontal", label: "Menu", action: openGuide),
            ] : [
                CouchHint(glyph: "A", label: "Details", action: { handle(.accept) }),
                CouchHint(glyph: "line.3.horizontal", label: "Menu", action: openGuide),
            ])
            .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// The shelves, stacked: the focused one on top and the next one's title
    /// peeking below, fading out. Moving up or down slides the stack.
    private func shelfStack(coverHeight: CGFloat) -> some View {
        let rowHeight = coverHeight * 1.16 + 26
        let spacing: CGFloat = 8
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(shelves.enumerated()), id: \.element.id) { index, shelf in
                CouchShelfRow(shelf: shelf, focusedColumn: focus.column(index, in: shelves),
                              active: index == focus.shelf, coverHeight: coverHeight) { column in
                    if index == focus.shelf, column == focus.column(index, in: shelves) {
                        handle(.accept)
                    } else {
                        focus.select(shelf: index, column: column)
                    }
                }
                .frame(height: rowHeight, alignment: .top)
                .opacity(index < focus.shelf ? 0 : index == focus.shelf ? 1 : 0.5)
            }
        }
        .offset(y: -CGFloat(focus.shelf) * (rowHeight + spacing))
        .frame(height: rowHeight + 28, alignment: .top)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom)
                .padding(.horizontal, -400))
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: focus.shelf)
    }

    // MARK: - Input

    private func handle(_ command: CouchCommand) {
        if guideOpen {
            switch command {
            case .up: guideIndex = max(0, guideIndex - 1)
            case .down: guideIndex = min(CouchGuideItem.allCases.count - 1, guideIndex + 1)
            case .accept: activate(CouchGuideItem.allCases[guideIndex])
            case .back, .menu: guideOpen = false
            default: break
            }
            return
        }
        if let game = pageGame {
            switch command {
            case .left: pageButton = 0
            case .right: pageButton = 1
            case .accept: pageButton == 0 ? primary(game) : properties(game)
            case .back: pageID = nil
            case .menu: openGuide()
            default: break
            }
            return
        }
        switch command {
        case .up, .down, .left, .right:
            focus.move(command, in: shelves)
        case .accept:
            if let game = focusedGame { pageButton = 0; pageID = game.id }
            else if shelves.isEmpty { guideAction(.library) }
        case .menu:
            openGuide()
        default:
            break
        }
    }

    /// The page's main button: Play, Install, or nothing while downloading.
    private func primary(_ game: CouchGame) {
        switch game.state {
        case .installed: play(game)
        case .notInstalled: install(game)
        case .downloading: break
        }
    }

    private func openGuide() {
        guideIndex = 0
        guideOpen = true
    }

    private func activate(_ item: CouchGuideItem) {
        guideOpen = false
        if item == .home { pageID = nil } else { guideAction(item) }
    }

    /// Loads the heroes of the covers around the focus before it gets there.
    private func prefetchNeighbours() {
        guard shelves.indices.contains(focus.shelf) else { return }
        var games: [CouchGame] = []
        let row = shelves[focus.shelf].games
        let column = focus.column(focus.shelf, in: shelves)
        games += row[max(0, column - 1)..<min(row.count, column + 3)]
        for index in [focus.shelf - 1, focus.shelf + 1] where shelves.indices.contains(index) {
            if let game = shelves[index].games[couchSafe: focus.column(index, in: shelves)] { games.append(game) }
        }
        CouchImageCache.shared.prefetch(games.compactMap(\.hero), maxPixel: 1800)
        CouchImageCache.shared.prefetch(games.compactMap(\.logo), maxPixel: 900)
    }
}

private extension Array {
    // Not `safe:`: Madeira's LibraryGridZoom.swift declares that one app-wide.
    subscript(couchSafe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
