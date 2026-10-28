import Foundation

/// Couch mode's input. The raw values are the names LibraryController.commands
/// sends (Library.swift): D-pad or left stick, A accept, B back, Y add, Start
/// menu, either shoulder tab. So Madeira's pad events map one to one.
enum CouchCommand: String, CaseIterable {
    case up, down, left, right, accept, back, add, menu, tab
}

/// Which cover has the focus: a shelf, and in each shelf the column it was
/// left at, so moving up and back down returns to the same game, as Big
/// Picture does.
struct CouchFocus: Equatable {
    var shelf = 0
    private var columns: [Int: Int] = [:]

    func column(_ shelf: Int, in shelves: [CouchShelf]) -> Int {
        guard shelves.indices.contains(shelf) else { return 0 }
        return min(columns[shelf] ?? 0, max(0, shelves[shelf].games.count - 1))
    }

    func game(in shelves: [CouchShelf]) -> CouchGame? {
        guard shelves.indices.contains(shelf) else { return shelves.first?.games.first }
        let games = shelves[shelf].games
        return games.isEmpty ? nil : games[column(shelf, in: shelves)]
    }

    /// Moves for a direction; false when already at that edge.
    @discardableResult
    mutating func move(_ command: CouchCommand, in shelves: [CouchShelf]) -> Bool {
        guard !shelves.isEmpty else { return false }
        shelf = min(shelf, shelves.count - 1)
        let column = column(shelf, in: shelves)
        let count = shelves[shelf].games.count
        switch command {
        case .up where shelf > 0: shelf -= 1
        case .down where shelf < shelves.count - 1: shelf += 1
        case .left where column > 0: columns[shelf] = column - 1
        case .right where column < count - 1: columns[shelf] = column + 1
        default: return false
        }
        return true
    }

    /// Keeps the focus on the same game when the shelves change under it: a
    /// finished download moves a game to Installed and reorders the rows, and
    /// the focus follows it there.
    mutating func keep(_ id: String?, in shelves: [CouchShelf]) {
        guard let id else { return }
        let order = shelves.indices.contains(shelf) ? [shelf] + shelves.indices.filter { $0 != shelf } : Array(shelves.indices)
        for index in order {
            if let column = shelves[index].games.firstIndex(where: { $0.id == id }) {
                select(shelf: index, column: column)
                return
            }
        }
    }

    /// Focuses a cover directly (a tap).
    mutating func select(shelf: Int, column: Int) {
        self.shelf = shelf
        columns[shelf] = column
    }
}
