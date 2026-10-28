import SwiftUI

/// The guide's entries. Couch mode handles Home itself; the app hosting it
/// handles the rest (CouchHomeView.guideAction).
enum CouchGuideItem: Int, CaseIterable, Identifiable {
    case home, library, settings, jit, exit

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Madeira library"
        case .settings: return "Settings"
        case .jit: return "JIT"
        case .exit: return "Exit Couch mode"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.grid.2x2.fill"
        case .settings: return "gearshape.fill"
        case .jit: return "bolt.fill"
        case .exit: return "rectangle.portrait.and.arrow.right"
        }
    }
}

/// The guide: a menu sliding in from the leading edge over the dimmed screen,
/// opened with Start (Back+Start during a game, LibraryController's "menu").
struct CouchGuide: View {
    let selection: Int
    let status: CouchStatus
    var activate: (Int) -> Void
    var close: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 4) {
                Text("Madeira")
                    .font(.system(size: 22, weight: .heavy))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                ForEach(CouchGuideItem.allCases) { item in
                    Button { activate(item.rawValue) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).frame(width: 22)
                            Text(item.title)
                            Spacer()
                            if item == .jit {
                                Text(status.jitReady ? "Ready" : "Off")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(item.rawValue == selection ? Color.black.opacity(0.6) : (status.jitReady ? .green : .orange))
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .foregroundStyle(item.rawValue == selection ? .black : .white)
                        .background(item.rawValue == selection ? Color.white : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                CouchHintBar(hints: [CouchHint(glyph: "A", label: "Select", action: { activate(selection) }),
                                     CouchHint(glyph: "B", label: "Close", action: close)])
            }
            .padding(14)
            .frame(width: 300)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.35))
            .transition(.move(edge: .leading))
        }
    }
}
