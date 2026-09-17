const std = @import("std");
const AccessNode = @import("node.zig").AccessNode;

/// Maximum number of nodes a single accessibility tree can hold.
pub const MAX_NODES = 96;

/// A flattened, pre-order accessibility tree derived from a depth-annotated
/// `AccessNode` list.
///
/// Nodes are supplied in pre-order (parents before children, children
/// contiguous). Each node's `depth` field states its nesting level: 0 = a direct
/// child of the window (root), 1 = child of the preceding depth-0 node, etc.
///
/// All relationships are stored as `i32` indices into the flat node list;
/// `-1` means "none". The struct is a plain value type — zero allocations,
/// trivially copyable — so it can be snapshotted and read under a lock.
pub const AccessTree = struct {
    len: usize = 0,
    parent: [MAX_NODES]i32 = [_]i32{-1} ** MAX_NODES,
    first_child: [MAX_NODES]i32 = [_]i32{-1} ** MAX_NODES,
    last_child: [MAX_NODES]i32 = [_]i32{-1} ** MAX_NODES,
    next_sibling: [MAX_NODES]i32 = [_]i32{-1} ** MAX_NODES,
    prev_sibling: [MAX_NODES]i32 = [_]i32{-1} ** MAX_NODES,
    depth: [MAX_NODES]u16 = [_]u16{0} ** MAX_NODES,
    /// First and last top-level nodes (children of the window). -1 when empty.
    root_first: i32 = -1,
    root_last: i32 = -1,

    /// Compute the tree layout from a pre-order, depth-annotated node list.
    /// Nodes beyond MAX_NODES are ignored.
    pub fn compute(nodes: []const AccessNode) AccessTree {
        var t = AccessTree{};
        const n = @min(nodes.len, MAX_NODES);
        t.len = n;

        var stack: [MAX_NODES]usize = undefined;
        var sp: usize = 0;

        for (nodes[0..n], 0..) |node, i| {
            const d = node.depth;
            // Pop until the stack top is a strict ancestor of this node.
            while (sp > 0 and nodes[stack[sp - 1]].depth >= d) sp -= 1;
            t.depth[i] = d;

            if (sp == 0) {
                // Top-level node — sibling of other roots, parent is the window.
                t.parent[i] = -1;
                if (t.root_last == -1) {
                    t.root_first = @intCast(i);
                } else {
                    t.next_sibling[@intCast(t.root_last)] = @intCast(i);
                    t.prev_sibling[i] = t.root_last;
                }
                t.root_last = @intCast(i);
            } else {
                const p: usize = stack[sp - 1];
                const pi: i32 = @intCast(p);
                t.parent[i] = pi;
                if (t.last_child[p] == -1) {
                    t.first_child[p] = @intCast(i);
                } else {
                    t.next_sibling[@intCast(t.last_child[p])] = @intCast(i);
                    t.prev_sibling[i] = t.last_child[p];
                }
                t.last_child[p] = @intCast(i);
            }

            stack[sp] = i;
            sp += 1;
        }
        return t;
    }

    /// Number of direct children of node `i`.
    pub fn childCount(self: *const AccessTree, i: usize) usize {
        var count: usize = 0;
        var k = self.first_child[i];
        while (k != -1) : (k = self.next_sibling[@intCast(k)]) count += 1;
        return count;
    }

    /// True when node `i` is a direct child of the window (no parent node).
    pub fn isRoot(self: *const AccessTree, i: usize) bool {
        return self.parent[i] == -1;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

fn mk(depth: u16) AccessNode {
    return .{ .role = .group, .name = "", .bounds = .{ .x = 0, .y = 0, .width = 0, .height = 0 }, .depth = depth };
}

test "AccessTree.compute: empty" {
    const t = AccessTree.compute(&.{});
    try std.testing.expectEqual(@as(usize, 0), t.len);
    try std.testing.expectEqual(@as(i32, -1), t.root_first);
    try std.testing.expectEqual(@as(i32, -1), t.root_last);
}

test "AccessTree.compute: flat list (all roots)" {
    const nodes = [_]AccessNode{ mk(0), mk(0), mk(0) };
    const t = AccessTree.compute(&nodes);
    try std.testing.expectEqual(@as(usize, 3), t.len);
    try std.testing.expectEqual(@as(i32, 0), t.root_first);
    try std.testing.expectEqual(@as(i32, 2), t.root_last);
    for (0..3) |i| {
        try std.testing.expect(t.isRoot(i));
        try std.testing.expectEqual(@as(i32, -1), t.parent[i]);
        try std.testing.expectEqual(@as(usize, 0), t.childCount(i));
    }
    try std.testing.expectEqual(@as(i32, 1), t.next_sibling[0]);
    try std.testing.expectEqual(@as(i32, 2), t.next_sibling[1]);
    try std.testing.expectEqual(@as(i32, -1), t.next_sibling[2]);
    try std.testing.expectEqual(@as(i32, -1), t.prev_sibling[0]);
    try std.testing.expectEqual(@as(i32, 0), t.prev_sibling[1]);
    try std.testing.expectEqual(@as(i32, 1), t.prev_sibling[2]);
}

test "AccessTree.compute: nested groups" {
    // 0: root A
    //   1: child
    //   2: child
    // 3: root B
    //   4: child
    const nodes = [_]AccessNode{ mk(0), mk(1), mk(1), mk(0), mk(1) };
    const t = AccessTree.compute(&nodes);

    try std.testing.expectEqual(@as(i32, -1), t.parent[0]);
    try std.testing.expectEqual(@as(i32, 0), t.parent[1]);
    try std.testing.expectEqual(@as(i32, 0), t.parent[2]);
    try std.testing.expectEqual(@as(i32, -1), t.parent[3]);
    try std.testing.expectEqual(@as(i32, 3), t.parent[4]);

    try std.testing.expectEqual(@as(i32, 1), t.first_child[0]);
    try std.testing.expectEqual(@as(i32, 2), t.last_child[0]);
    try std.testing.expectEqual(@as(usize, 2), t.childCount(0));
    try std.testing.expectEqual(@as(usize, 0), t.childCount(1));

    try std.testing.expectEqual(@as(i32, 2), t.next_sibling[1]);
    try std.testing.expectEqual(@as(i32, -1), t.next_sibling[2]);
    try std.testing.expectEqual(@as(i32, 1), t.prev_sibling[2]);

    try std.testing.expectEqual(@as(i32, 0), t.root_first);
    try std.testing.expectEqual(@as(i32, 3), t.root_last);
    try std.testing.expectEqual(@as(i32, 3), t.next_sibling[0]);
    try std.testing.expectEqual(@as(i32, 4), t.first_child[3]);
    try std.testing.expectEqual(@as(i32, 4), t.last_child[3]);
}

test "AccessTree.compute: deep nesting" {
    // 0: root
    //   1: child
    //     2: grandchild
    //   3: child (sibling of 1)
    const nodes = [_]AccessNode{ mk(0), mk(1), mk(2), mk(1) };
    const t = AccessTree.compute(&nodes);

    try std.testing.expectEqual(@as(i32, 0), t.parent[1]);
    try std.testing.expectEqual(@as(i32, 1), t.parent[2]);
    try std.testing.expectEqual(@as(i32, 0), t.parent[3]);

    try std.testing.expectEqual(@as(i32, 2), t.first_child[1]);
    try std.testing.expectEqual(@as(i32, 3), t.next_sibling[1]);
    try std.testing.expectEqual(@as(i32, -1), t.next_sibling[2]);
    try std.testing.expectEqual(@as(i32, 1), t.prev_sibling[3]);
    try std.testing.expectEqual(@as(usize, 1), t.childCount(1));
}

test "AccessTree.compute: multiple roots with subtrees" {
    // 0: A     1: A child   2: B     3: B child
    const nodes = [_]AccessNode{ mk(0), mk(1), mk(0), mk(1) };
    const t = AccessTree.compute(&nodes);
    try std.testing.expectEqual(@as(i32, 0), t.root_first);
    try std.testing.expectEqual(@as(i32, 2), t.root_last);
    try std.testing.expectEqual(@as(i32, 2), t.next_sibling[0]);
    try std.testing.expectEqual(@as(i32, 1), t.first_child[0]);
    try std.testing.expectEqual(@as(i32, 3), t.first_child[2]);
}

test "AccessTree.compute: clamps to MAX_NODES" {
    var nodes: [MAX_NODES + 10]AccessNode = undefined;
    for (&nodes) |*n| n.* = mk(0);
    const t = AccessTree.compute(&nodes);
    try std.testing.expectEqual(@as(usize, MAX_NODES), t.len);
    try std.testing.expectEqual(@as(i32, @intCast(MAX_NODES - 1)), t.root_last);
}
