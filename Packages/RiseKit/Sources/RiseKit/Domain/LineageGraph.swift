import Foundation

/// Lineage graph over cultures built from `split` events.
///
/// Edges point parent → child. The graph must stay acyclic; adding an
/// edge that would close a cycle is rejected with
/// `RiseLogError.lineageCycle(parent:child:)`.
public struct LineageGraph: Sendable {
    /// parent -> set of children
    private var children: [CultureID: Set<CultureID>] = [:]
    /// child -> set of parents (a culture can be split from multiple parents)
    private var parents: [CultureID: Set<CultureID>] = [:]

    public init() {}

    public var edgeCount: Int {
        children.values.reduce(0) { $0 + $1.count }
    }

    /// Direct parents of a culture.
    public func parents(of child: CultureID) -> Set<CultureID> {
        parents[child] ?? []
    }

    /// Direct children of a culture.
    public func children(of parent: CultureID) -> Set<CultureID> {
        children[parent] ?? []
    }

    /// Adds a parent → child edge.
    ///
    /// A cycle exists iff `child` can already reach `parent` by walking
    /// existing parent→child edges (or `child == parent`). In that case the
    /// edge is rejected and the graph is left untouched.
    public mutating func addEdge(parent: CultureID, child: CultureID) throws {
        if parent == child || reaches(from: child, to: parent) {
            throw RiseLogError.lineageCycle(parent: parent, child: child)
        }
        children[parent, default: []].insert(child)
        parents[child, default: []].insert(parent)
    }

    /// True if `target` is reachable from `source` following parent→child edges.
    private func reaches(from source: CultureID, to target: CultureID) -> Bool {
        var seen: Set<CultureID> = [source]
        var stack = [source]
        while let current = stack.popLast() {
            for next in children[current] ?? [] {
                if next == target { return true }
                if seen.insert(next).inserted {
                    stack.append(next)
                }
            }
        }
        return false
    }

    /// All descendants (children, grandchildren, …) of a culture.
    public func descendants(of culture: CultureID) -> Set<CultureID> {
        var result: Set<CultureID> = []
        var stack = [culture]
        while let current = stack.popLast() {
            for next in children[current] ?? [] where result.insert(next).inserted {
                stack.append(next)
            }
        }
        return result
    }

    /// All ancestors (parents, grandparents, …) of a culture.
    public func ancestors(of culture: CultureID) -> Set<CultureID> {
        var result: Set<CultureID> = []
        var stack = [culture]
        while let current = stack.popLast() {
            for next in parents[current] ?? [] where result.insert(next).inserted {
                stack.append(next)
            }
        }
        return result
    }

    /// Builds a lineage graph from split payloads already in a ledger.
    ///
    /// Split events are processed in occurredAt order; edges that would
    /// create a cycle are rejected (thrown), matching the mutation API.
    public static func build(from ledger: EventLedger, knownCultureIds: Set<CultureID>) throws -> LineageGraph {
        let splits = ledger.allEvents
            .compactMap { event -> (Date, CultureID, CultureID)? in
                guard case .split(let parent, let separatedAt) = event.payload else { return nil }
                return (separatedAt, event.cultureId, parent)
            }
            .sorted { $0.0 < $1.0 }

        var graph = LineageGraph()
        for (_, child, parent) in splits {
            guard knownCultureIds.contains(child) else {
                throw RiseLogError.unknownCulture(child)
            }
            guard knownCultureIds.contains(parent) else {
                throw RiseLogError.unknownParent(parent)
            }
            try graph.addEdge(parent: parent, child: child)
        }
        return graph
    }
}
