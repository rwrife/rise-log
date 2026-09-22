import Foundation
import Testing

@testable import RiseKit

@Suite("Lineage DAG and cycle rejection")
struct LineageTests {
    let parent = CultureID(rawValue: "parent")
    let child = CultureID(rawValue: "child")
    let grandchild = CultureID(rawValue: "grandchild")

    @Test("split edges build a DAG with parents and children queries")
    func basicDag() throws {
        var graph = LineageGraph()
        try graph.addEdge(parent: parent, child: child)
        try graph.addEdge(parent: child, child: grandchild)

        #expect(graph.parents(of: child) == [parent])
        #expect(graph.children(of: parent) == [child])
        #expect(graph.descendants(of: parent) == [child, grandchild])
        #expect(graph.ancestors(of: grandchild) == [parent, child])
        #expect(graph.edgeCount == 2)
    }

    @Test("self-edge (culture split from itself) is rejected as a cycle")
    func selfEdgeRejected() {
        var graph = LineageGraph()
        #expect(throws: RiseLogError.lineageCycle(parent: parent, child: parent)) {
            try graph.addEdge(parent: parent, child: parent)
        }
        #expect(graph.edgeCount == 0)
    }

    @Test("direct back-edge closing a 2-node cycle is rejected")
    func directCycleRejected() throws {
        var graph = LineageGraph()
        try graph.addEdge(parent: parent, child: child)
        #expect(throws: RiseLogError.lineageCycle(parent: child, child: parent)) {
            try graph.addEdge(parent: child, child: parent)
        }
        // Graph untouched by the rejected edge.
        #expect(graph.edgeCount == 1)
        #expect(graph.children(of: child).isEmpty)
    }

    @Test("transitive back-edge closing a 3-node cycle is rejected")
    func transitiveCycleRejected() throws {
        var graph = LineageGraph()
        try graph.addEdge(parent: parent, child: child)
        try graph.addEdge(parent: child, child: grandchild)
        #expect(throws: RiseLogError.lineageCycle(parent: grandchild, child: parent)) {
            try graph.addEdge(parent: grandchild, child: parent)
        }
        #expect(graph.edgeCount == 2)
    }

    @Test("diamond lineage (two parents, shared ancestor) is legal")
    func diamondAllowed() throws {
        let otherParent = CultureID(rawValue: "other")
        let merged = CultureID(rawValue: "merged")
        var graph = LineageGraph()
        try graph.addEdge(parent: parent, child: merged)
        try graph.addEdge(parent: otherParent, child: merged)
        try graph.addEdge(parent: parent, child: otherParent) // other was split from parent
        #expect(graph.parents(of: merged) == [parent, otherParent])
        #expect(graph.ancestors(of: merged) == [parent, otherParent])
    }

    @Test("graph builds from ledger split events in separation order")
    func buildFromLedger() throws {
        var ledger = EventLedger()
        let sep1 = TestFixtures.date(TestFixtures.utc, 2026, 2, 1)
        let sep2 = TestFixtures.date(TestFixtures.utc, 2026, 3, 1)
        try ledger.append(TestFixtures.event(
            "s1", culture: "child", kind: .split, at: sep1,
            payload: .split(parent: parent, separatedAt: sep1)))
        try ledger.append(TestFixtures.event(
            "s2", culture: "grandchild", kind: .split, at: sep2,
            payload: .split(parent: child, separatedAt: sep2)))

        let graph = try LineageGraph.build(from: ledger, knownCultureIds: [parent, child, grandchild])
        #expect(graph.parents(of: child) == [parent])
        #expect(graph.parents(of: grandchild) == [child])
    }

    @Test("build from ledger rejects a cycle-forming split")
    func buildFromLedgerCycle() throws {
        var ledger = EventLedger()
        let sep1 = TestFixtures.date(TestFixtures.utc, 2026, 2, 1)
        let sep2 = TestFixtures.date(TestFixtures.utc, 2026, 3, 1)
        try ledger.append(TestFixtures.event(
            "s1", culture: "child", kind: .split, at: sep1,
            payload: .split(parent: parent, separatedAt: sep1)))
        // child claims to be the parent of its own ancestor → cycle.
        try ledger.append(TestFixtures.event(
            "s2", culture: "parent", kind: .split, at: sep2,
            payload: .split(parent: child, separatedAt: sep2)))

        #expect(throws: RiseLogError.lineageCycle(parent: child, child: parent)) {
            _ = try LineageGraph.build(from: ledger, knownCultureIds: [parent, child])
        }
    }

    @Test("build rejects split edges referencing unknown cultures")
    func buildUnknownReferences() throws {
        var ledger = EventLedger()
        let sep = TestFixtures.date(TestFixtures.utc, 2026, 2, 1)
        try ledger.append(TestFixtures.event(
            "s1", culture: "child", kind: .split, at: sep,
            payload: .split(parent: parent, separatedAt: sep)))

        #expect(throws: RiseLogError.unknownParent(parent)) {
            _ = try LineageGraph.build(from: ledger, knownCultureIds: [child])
        }
        #expect(throws: RiseLogError.unknownCulture(child)) {
            _ = try LineageGraph.build(from: ledger, knownCultureIds: [parent])
        }
    }
}
