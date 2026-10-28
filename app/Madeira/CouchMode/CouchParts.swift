import SwiftUI
import UIKit

// The pieces Couch mode's screens are built from.

/// The focused game's hero art filling the screen, darkened toward the text and
/// shelves, cross-fading when the focus moves.
struct CouchBackdrop: View {
    let game: CouchGame?
    /// Darker, for the game page and the guide.
    var deep = false

    var body: some View {
        ZStack {
            Color.black
            if let game {
                CouchImage(game.hero, maxPixel: 1800) { _ in CouchFallbackArt(title: game.title) }
                    .id(game.id)
                    .transition(.opacity)
            }
            LinearGradient(stops: [.init(color: .black.opacity(deep ? 0.92 : 0.82), location: 0),
                                   .init(color: .black.opacity(deep ? 0.6 : 0.25), location: 0.55),
                                   .init(color: .black.opacity(deep ? 0.5 : 0.1), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.3),
                                   .init(color: .black.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.4), value: game?.id)
        .ignoresSafeArea()
    }
}

/// Artwork for a game with none: a gradient tinted from its title.
struct CouchFallbackArt: View {
    let title: String
    var showsTitle = false

    var body: some View {
        // String.hashValue changes every run; this keeps a game's colour.
        let seed = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.45),
                                    Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if showsTitle {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
            }
        }
    }
}

/// One cover. The focused one grows and glows; Library games show a download
/// mark and downloads their progress.
struct CouchCover: View {
    let game: CouchGame
    let focused: Bool
    let height: CGFloat

    var body: some View {
        CouchImage(game.cover, maxPixel: 600) { _ in CouchFallbackArt(title: game.title, showsTitle: true) }
            .frame(width: (height * 2 / 3).rounded(), height: height)
            .saturation(game.state == .notInstalled ? 0.6 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) { badge.padding(6) }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.95 : 0.08), lineWidth: focused ? 2.5 : 1)
            }
            .shadow(color: .white.opacity(focused ? 0.28 : 0), radius: 16)
            .shadow(color: .black.opacity(0.5), radius: focused ? 12 : 4, y: focused ? 8 : 2)
            .scaleEffect(focused ? 1.1 : 1)
            .zIndex(focused ? 1 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: focused)
            .accessibilityLabel(game.title)
    }

    @ViewBuilder private var badge: some View {
        switch game.state {
        case .installed:
            EmptyView()
        case .notInstalled:
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
        case .downloading(let progress):
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: progress).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            .padding(3)
            .background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// A shelf: its title and a horizontal row of covers that scrolls to keep the
/// focused one near the leading edge.
struct CouchShelfRow: View {
    let shelf: CouchShelf
    let focusedColumn: Int
    let active: Bool
    let coverHeight: CGFloat
    var tap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(shelf.title).font(.system(size: 15, weight: .bold))
                Text("\(shelf.games.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(shelf.games.enumerated()), id: \.element.id) { column, game in
                            CouchCover(game: game, focused: active && column == focusedColumn, height: coverHeight)
                                .id(game.id)
                                .onTapGesture { tap(column) }
                        }
                    }
                    .padding(.vertical, coverHeight * 0.08)
                    .padding(.horizontal, coverHeight * 0.06)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onChange(of: focusedColumn) { _, column in
                    guard shelf.games.indices.contains(column) else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(shelf.games[column].id, anchor: UnitPoint(x: 0.12, y: 0.5))
                    }
                }
            }
        }
    }
}

/// The focused game's title (its logo when Steam has one) and a line about it.
struct CouchGameInfo: View {
    let game: CouchGame?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let game {
                CouchLogo(game: game, height: large ? 96 : 64)
                CouchMetaLine(game: game)
            }
        }
        .id(game?.id)
        .transition(.opacity.combined(with: .offset(y: 6)))
        .animation(.easeOut(duration: 0.25), value: game?.id)
    }
}

struct CouchLogo: View {
    let game: CouchGame
    let height: CGFloat

    var body: some View {
        CouchImage(game.logo, maxPixel: 900, fill: false) { failed in
            if failed {
                Text(game.title)
                    .font(.system(size: height * 0.5, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.6), radius: 8)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: height * 4.6, maxHeight: height, alignment: .leading)
        .frame(height: height, alignment: .bottomLeading)
        .shadow(color: .black.opacity(0.5), radius: 10)
    }
}

struct CouchMetaLine: View {
    let game: CouchGame

    var body: some View {
        HStack(spacing: 10) {
            CouchStatePill(state: game.state)
            let details = [game.lastPlayedText, game.playtimeText, game.state == .installed ? nil : game.sizeText].compactMap { $0 }
            Text(details.joined(separator: "  ·  "))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }
}

struct CouchStatePill: View {
    let state: CouchGame.State

    var body: some View {
        let (symbol, text, tint): (String, String, Color) = {
            switch state {
            case .installed: return ("checkmark.circle.fill", "Ready to play", .green)
            case .notInstalled: return ("arrow.down.circle", "Not installed", .white)
            case .downloading(let p): return ("arrow.down.circle.fill", "Downloading \(Int(p * 100))%", .cyan)
            }
        }()
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.12), in: Capsule())
    }
}

/// The home screen with no games: what to do next, instead of a blank screen.
struct CouchEmptyLibrary: View {
    var openLibrary: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "gamecontroller")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("No games yet")
                .font(.system(size: 24, weight: .heavy))
            Text("Sign in to Steam in Madeira's library to see the games you own, or add a game with + there.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            CouchPageButton(label: "Open Madeira library", symbol: "square.grid.2x2.fill", prominent: true,
                            focused: true, progress: nil, action: openLibrary)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Title, JIT state, controller, battery and clock.
struct CouchTopBar: View {
    let title: String
    let status: CouchStatus
    @State private var battery: Float = -1

    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 20, weight: .heavy))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(status.jitReady ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(status.jitReady ? "JIT ready" : "JIT off")
            }
            if status.controllerConnected {
                Image(systemName: "gamecontroller.fill")
            }
            if battery >= 0 {
                Image(systemName: battery > 0.75 ? "battery.100" : battery > 0.4 ? "battery.50" : "battery.25")
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = UIDevice.current.batteryLevel
        }
    }
}

/// A button hint along the bottom ("Ⓐ Play"). Hints are also buttons, for touch.
struct CouchHint: Identifiable {
    var glyph: String
    var label: String
    var action: (() -> Void)?
    var id: String { glyph + label }
}

struct CouchHintBar: View {
    let hints: [CouchHint]

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            ForEach(hints) { hint in
                Button { hint.action?() } label: {
                    HStack(spacing: 6) {
                        CouchGlyph(glyph: hint.glyph)
                        Text(hint.label).font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .disabled(hint.action == nil)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

/// A controller button: a letter in a circle, or an SF Symbol for Menu.
struct CouchGlyph: View {
    let glyph: String

    var body: some View {
        Group {
            if glyph.count == 1 {
                Text(glyph).font(.system(size: 11, weight: .heavy))
            } else {
                Image(systemName: glyph).font(.system(size: 10, weight: .heavy))
            }
        }
        .frame(width: 20, height: 20)
        .foregroundStyle(.black)
        .background(.white.opacity(0.92), in: Circle())
    }
}
