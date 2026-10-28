import SwiftUI

/// A game's page: its logo large over the hero, Play (or Install) and
/// Properties, and what Madeira knows about it. B goes back.
struct CouchGamePage: View {
    let game: CouchGame
    let status: CouchStatus
    /// 0 = the main button, 1 = Properties.
    let selection: Int
    var primary: () -> Void
    var properties: () -> Void
    var close: () -> Void
    var menu: () -> Void
    var select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CouchTopBar(title: game.isSteam ? "Steam" : "Other games", status: status)
                .opacity(0.8)
            Spacer(minLength: 8)
            CouchGameInfo(game: game, large: true)
            HStack(spacing: 12) {
                CouchPageButton(label: primaryLabel, symbol: primarySymbol, prominent: true,
                                focused: selection == 0, progress: progress) { select(0); primary() }
                CouchPageButton(label: "Properties", symbol: "gearshape.fill", prominent: false,
                                focused: selection == 1, progress: nil) { select(1); properties() }
            }
            .padding(.top, 18)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                // Steam reports playtime; for games added to the library Madeira keeps only the last start.
                CouchFact(title: "Playtime", value: game.playtimeText ?? (game.lastPlayed == nil ? "Never played" : "—"))
                CouchFact(title: "Last played", value: game.lastPlayedText?.replacingOccurrences(of: "Last played ", with: "") ?? "—")
                CouchFact(title: "Size", value: game.sizeText ?? "—")
                if game.isSteam {
                    CouchFact(title: "Steam Cloud", value: game.cloudSaves ? "Saves sync" : "Not used")
                }
            }
            CouchHintBar(hints: [
                CouchHint(glyph: "A", label: primaryLabel, action: primary),
                CouchHint(glyph: "B", label: "Back", action: close),
                CouchHint(glyph: "line.3.horizontal", label: "Menu", action: menu),
            ])
            .padding(.top, 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var primaryLabel: String {
        switch game.state {
        case .installed: return "Play"
        case .notInstalled: return "Install"
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        }
    }

    private var primarySymbol: String {
        game.state == .installed ? "play.fill" : "arrow.down.to.line"
    }

    private var progress: Double? {
        if case .downloading(let p) = game.state { return p }
        return nil
    }
}

struct CouchPageButton: View {
    let label: String
    let symbol: String
    let prominent: Bool
    let focused: Bool
    let progress: Double?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .padding(.horizontal, prominent ? 26 : 18)
                .frame(height: 44)
                .foregroundStyle(focused ? .black : .white)
                .background {
                    ZStack(alignment: .leading) {
                        Capsule().fill(focused ? Color.white : (prominent ? Color.green.opacity(0.85) : Color.white.opacity(0.14)))
                        if let progress {
                            GeometryReader { geo in
                                Capsule().fill(Color.cyan.opacity(0.55)).frame(width: geo.size.width * progress)
                            }
                        }
                    }
                }
                .overlay { Capsule().strokeBorder(.white.opacity(focused ? 0 : 0.15)) }
                .scaleEffect(focused ? 1.06 : 1)
                .shadow(color: .white.opacity(focused ? 0.3 : 0), radius: 12)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: focused)
        }
        .buttonStyle(.plain)
    }
}

struct CouchFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 120, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
