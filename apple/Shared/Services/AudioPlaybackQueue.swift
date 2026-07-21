import Foundation

// Adapted from MeloX (GPL-3.0): queue ordering and playback snapshot persistence.
struct AudioPlaybackSnapshot: Codable {
    let queue: [LibraryItem]
    let currentIndex: Int
    let progress: TimeInterval
    let repeatMode: String
    let isShuffled: Bool
    let shuffledOrder: [Int]
    let playbackRate: Float
    let volume: Double

    init(
        queue: [LibraryItem],
        currentIndex: Int,
        progress: TimeInterval,
        repeatMode: String,
        isShuffled: Bool,
        shuffledOrder: [Int],
        playbackRate: Float,
        volume: Double = 1
    ) {
        self.queue = queue
        self.currentIndex = currentIndex
        self.progress = progress
        self.repeatMode = repeatMode
        self.isShuffled = isShuffled
        self.shuffledOrder = shuffledOrder
        self.playbackRate = playbackRate
        self.volume = volume
    }

    private enum CodingKeys: String, CodingKey {
        case queue
        case currentIndex
        case progress
        case repeatMode
        case isShuffled
        case shuffledOrder
        case playbackRate
        case volume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queue = try container.decode([LibraryItem].self, forKey: .queue)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        progress = try container.decode(TimeInterval.self, forKey: .progress)
        repeatMode = try container.decode(String.self, forKey: .repeatMode)
        isShuffled = try container.decode(Bool.self, forKey: .isShuffled)
        shuffledOrder = try container.decode([Int].self, forKey: .shuffledOrder)
        playbackRate = try container.decode(Float.self, forKey: .playbackRate)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1
    }
}

struct AudioPlaybackQueue {
    private(set) var items: [LibraryItem] = []
    private(set) var currentIndex = 0
    private(set) var isShuffled = false

    private var shuffledOrder: [Int] = []
    private var shuffledPosition = 0

    var currentItem: LibraryItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var persistedShuffleOrder: [Int] {
        shuffledOrder
    }

    mutating func restore(
        items: [LibraryItem],
        currentIndex: Int,
        isShuffled: Bool,
        shuffledOrder: [Int]
    ) {
        self.items = items.filter { $0.kind == .music && FileManager.default.fileExists(atPath: $0.url.path) }
        self.currentIndex = self.items.isEmpty ? 0 : min(max(currentIndex, 0), self.items.count - 1)
        self.isShuffled = isShuffled

        if isShuffled, isValidShuffleOrder(shuffledOrder) {
            self.shuffledOrder = shuffledOrder
            shuffledPosition = shuffledOrder.firstIndex(of: self.currentIndex) ?? 0
        } else if isShuffled {
            rebuildShuffleOrder()
        } else {
            self.shuffledOrder = []
            shuffledPosition = 0
        }
    }

    mutating func replace(with items: [LibraryItem], startingAt index: Int) {
        let filtered = items.filter { $0.kind == .music }
        self.items = filtered
        currentIndex = filtered.isEmpty ? 0 : min(max(index, 0), filtered.count - 1)
        if isShuffled {
            rebuildShuffleOrder()
        }
    }

    mutating func select(item: LibraryItem) -> Bool {
        guard let index = items.firstIndex(of: item) else { return false }
        return select(index: index)
    }

    mutating func select(index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        currentIndex = index
        alignShufflePosition()
        return true
    }

    mutating func move(by offset: Int, wraps: Bool) -> Bool {
        let order = isShuffled ? shuffledOrder : Array(items.indices)
        guard !order.isEmpty else { return false }
        let position = isShuffled ? shuffledPosition : currentIndex
        var destination = position + offset

        if order.indices.contains(destination) {
            // Keep walking the existing order.
        } else if wraps {
            destination = offset > 0 ? 0 : order.count - 1
        } else {
            return false
        }

        if isShuffled {
            shuffledPosition = destination
            currentIndex = order[destination]
        } else {
            currentIndex = destination
        }
        return true
    }

    mutating func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            rebuildShuffleOrder()
        } else {
            shuffledOrder = []
            shuffledPosition = 0
        }
    }

    private mutating func rebuildShuffleOrder() {
        guard items.indices.contains(currentIndex) else {
            shuffledOrder = []
            shuffledPosition = 0
            return
        }
        shuffledOrder = [currentIndex] + items.indices.filter { $0 != currentIndex }.shuffled()
        shuffledPosition = 0
    }

    private mutating func alignShufflePosition() {
        guard isShuffled else { return }
        if let position = shuffledOrder.firstIndex(of: currentIndex) {
            shuffledPosition = position
        } else {
            rebuildShuffleOrder()
        }
    }

    private func isValidShuffleOrder(_ order: [Int]) -> Bool {
        order.count == items.count && Set(order) == Set(items.indices)
    }
}

@MainActor
final class AudioPlaybackPersistence {
    private enum Key {
        static let snapshot = "yubing.audioPlaybackSnapshot"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AudioPlaybackSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshot) else { return nil }
        return try? JSONDecoder().decode(AudioPlaybackSnapshot.self, from: data)
    }

    func save(_ snapshot: AudioPlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshot)
    }

    func clear() {
        defaults.removeObject(forKey: Key.snapshot)
    }
}
