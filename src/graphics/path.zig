const std = @import("std");

/// A 2D point in path space (floating point, unlike layout's integer `Point`).
pub const Vec2 = struct { x: f32, y: f32 };

pub const Cubic = struct { c1: Vec2, c2: Vec2, to: Vec2 };
pub const Quad = struct { c: Vec2, to: Vec2 };
pub const Arc = struct {
    rx: f32,
    ry: f32,
    rotation: f32,
    large_arc: bool,
    sweep: bool,
    to: Vec2,
};

/// One absolute, fully-resolved path command. Relative SVG commands are
/// converted to absolute coordinates during parsing.
pub const Cmd = union(enum) {
    move_to: Vec2,
    line_to: Vec2,
    cubic: Cubic,
    quad: Quad,
    arc: Arc,
    close: void,
};

pub const ParseError = error{ InvalidPath, OutOfSpace };

/// Parse an SVG path `d` string into `out`. Returns the number of commands
/// written. Supports M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z, implicit repeated
/// commands, and implicit number separators (e.g. `10-5`, `1.5.5`).
pub fn parse(src: []const u8, out: []Cmd) ParseError!usize {
    var p = Parser{ .s = src };
    var count: usize = 0;

    var cur = Vec2{ .x = 0, .y = 0 };
    var sub = Vec2{ .x = 0, .y = 0 };
    var last_cubic_c2 = Vec2{ .x = 0, .y = 0 };
    var last_quad_c = Vec2{ .x = 0, .y = 0 };
    const Kind = enum { none, cubic, quad };
    var last_kind: Kind = .none;

    var letter: u8 = 0;
    var started = false;

    while (true) {
        p.skipSep();
        if (p.i >= p.s.len) break;
        const ch = p.s[p.i];
        if (isCmd(ch)) {
            p.i += 1;
            letter = ch;
        } else if (!started) {
            return error.InvalidPath;
        }
        started = true;

        const rel = letter >= 'a';
        const upper = std.ascii.toUpper(letter);

        switch (upper) {
            'M' => {
                const x = try p.num();
                const y = try p.num();
                cur = if (rel) .{ .x = cur.x + x, .y = cur.y + y } else .{ .x = x, .y = y };
                sub = cur;
                try put(out, &count, .{ .move_to = cur });
                last_kind = .none;
                // Subsequent implicit coordinate pairs are lineto.
                letter = if (rel) 'l' else 'L';
            },
            'L' => {
                const x = try p.num();
                const y = try p.num();
                cur = if (rel) .{ .x = cur.x + x, .y = cur.y + y } else .{ .x = x, .y = y };
                try put(out, &count, .{ .line_to = cur });
                last_kind = .none;
            },
            'H' => {
                const x = try p.num();
                cur.x = if (rel) cur.x + x else x;
                try put(out, &count, .{ .line_to = cur });
                last_kind = .none;
            },
            'V' => {
                const y = try p.num();
                cur.y = if (rel) cur.y + y else y;
                try put(out, &count, .{ .line_to = cur });
                last_kind = .none;
            },
            'C' => {
                const c1 = try p.rel(rel, cur);
                const c2 = try p.rel(rel, cur);
                const to = try p.rel(rel, cur);
                try put(out, &count, .{ .cubic = .{ .c1 = c1, .c2 = c2, .to = to } });
                last_cubic_c2 = c2;
                last_kind = .cubic;
                cur = to;
            },
            'S' => {
                const c1 = if (last_kind == .cubic) reflect(last_cubic_c2, cur) else cur;
                const c2 = try p.rel(rel, cur);
                const to = try p.rel(rel, cur);
                try put(out, &count, .{ .cubic = .{ .c1 = c1, .c2 = c2, .to = to } });
                last_cubic_c2 = c2;
                last_kind = .cubic;
                cur = to;
            },
            'Q' => {
                const c = try p.rel(rel, cur);
                const to = try p.rel(rel, cur);
                try put(out, &count, .{ .quad = .{ .c = c, .to = to } });
                last_quad_c = c;
                last_kind = .quad;
                cur = to;
            },
            'T' => {
                const c = if (last_kind == .quad) reflect(last_quad_c, cur) else cur;
                const to = try p.rel(rel, cur);
                try put(out, &count, .{ .quad = .{ .c = c, .to = to } });
                last_quad_c = c;
                last_kind = .quad;
                cur = to;
            },
            'A' => {
                const rx = try p.num();
                const ry = try p.num();
                const rot = try p.num();
                const large = try p.flag();
                const sweep = try p.flag();
                const to = try p.rel(rel, cur);
                try put(out, &count, .{ .arc = .{
                    .rx = rx,
                    .ry = ry,
                    .rotation = rot,
                    .large_arc = large,
                    .sweep = sweep,
                    .to = to,
                } });
                last_kind = .none;
                cur = to;
            },
            'Z' => {
                try put(out, &count, .{ .close = {} });
                cur = sub;
                last_kind = .none;
            },
            else => return error.InvalidPath,
        }
    }
    return count;
}

fn put(out: []Cmd, count: *usize, cmd: Cmd) ParseError!void {
    if (count.* >= out.len) return error.OutOfSpace;
    out[count.*] = cmd;
    count.* += 1;
}

fn reflect(p: Vec2, about: Vec2) Vec2 {
    return .{ .x = 2 * about.x - p.x, .y = 2 * about.y - p.y };
}

fn isCmd(c: u8) bool {
    return switch (c) {
        'M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c',
        'S', 's', 'Q', 'q', 'T', 't', 'A', 'a', 'Z', 'z' => true,
        else => false,
    };
}

const Parser = struct {
    s: []const u8,
    i: usize = 0,

    fn skipSep(self: *Parser) void {
        while (self.i < self.s.len) {
            const c = self.s[self.i];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == ',') {
                self.i += 1;
            } else break;
        }
    }

    /// Parse one number. Handles a leading sign, decimals, exponents, and
    /// implicit separators (a new `-` or `.` starts a fresh number).
    fn num(self: *Parser) ParseError!f32 {
        self.skipSep();
        const start = self.i;
        if (self.i < self.s.len and (self.s[self.i] == '+' or self.s[self.i] == '-')) self.i += 1;

        var saw_digit = false;
        while (self.i < self.s.len and std.ascii.isDigit(self.s[self.i])) : (self.i += 1) saw_digit = true;

        if (self.i < self.s.len and self.s[self.i] == '.') {
            self.i += 1;
            while (self.i < self.s.len and std.ascii.isDigit(self.s[self.i])) : (self.i += 1) saw_digit = true;
        }
        if (!saw_digit) return error.InvalidPath;

        // Optional exponent.
        if (self.i < self.s.len and (self.s[self.i] == 'e' or self.s[self.i] == 'E')) {
            const save = self.i;
            self.i += 1;
            if (self.i < self.s.len and (self.s[self.i] == '+' or self.s[self.i] == '-')) self.i += 1;
            var exp_digit = false;
            while (self.i < self.s.len and std.ascii.isDigit(self.s[self.i])) : (self.i += 1) exp_digit = true;
            if (!exp_digit) self.i = save;
        }

        return std.fmt.parseFloat(f32, self.s[start..self.i]) catch error.InvalidPath;
    }

    /// Parse an absolute or relative coordinate pair.
    fn rel(self: *Parser, relative: bool, cur: Vec2) ParseError!Vec2 {
        const x = try self.num();
        const y = try self.num();
        return if (relative) .{ .x = cur.x + x, .y = cur.y + y } else .{ .x = x, .y = y };
    }

    /// Parse an arc flag: a single `0` or `1` (may be adjacent to the next).
    fn flag(self: *Parser) ParseError!bool {
        self.skipSep();
        if (self.i >= self.s.len) return error.InvalidPath;
        const c = self.s[self.i];
        if (c == '0') {
            self.i += 1;
            return false;
        }
        if (c == '1') {
            self.i += 1;
            return true;
        }
        return error.InvalidPath;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

fn expectVec(v: Vec2, x: f32, y: f32) !void {
    try std.testing.expectApproxEqAbs(x, v.x, 1e-4);
    try std.testing.expectApproxEqAbs(y, v.y, 1e-4);
}

test "parse: absolute move + line" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M10 20 L30 40", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try expectVec(buf[0].move_to, 10, 20);
    try expectVec(buf[1].line_to, 30, 40);
}

test "parse: relative move + line" {
    var buf: [8]Cmd = undefined;
    const n = try parse("m10 20 l10 10", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try expectVec(buf[0].move_to, 10, 20);
    try expectVec(buf[1].line_to, 20, 30);
}

test "parse: implicit lineto after moveto" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 10 10 20 20", &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try expectVec(buf[0].move_to, 0, 0);
    try expectVec(buf[1].line_to, 10, 10);
    try expectVec(buf[2].line_to, 20, 20);
}

test "parse: implicit lineto stays relative after relative moveto" {
    var buf: [8]Cmd = undefined;
    const n = try parse("m0 0 10 10", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try expectVec(buf[1].line_to, 10, 10);
}

test "parse: H and V" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 H50 V50", &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try expectVec(buf[1].line_to, 50, 0);
    try expectVec(buf[2].line_to, 50, 50);
}

test "parse: close resets to subpath start" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 L10 0 L10 10 Z L5 5", &buf);
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expect(buf[3] == .close);
    // after Z, current point returns to (0,0); absolute L5 5 is unaffected
    try expectVec(buf[4].line_to, 5, 5);
}

test "parse: cubic" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 C0 10 10 10 10 0", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    const c = buf[1].cubic;
    try expectVec(c.c1, 0, 10);
    try expectVec(c.c2, 10, 10);
    try expectVec(c.to, 10, 0);
}

test "parse: smooth cubic reflects previous control point" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0", &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    const c = buf[2].cubic;
    // reflection of (10,10) about (10,0) is (10,-10)
    try expectVec(c.c1, 10, -10);
    try expectVec(c.c2, 20, -10);
    try expectVec(c.to, 20, 0);
}

test "parse: quad and smooth quad" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 Q5 10 10 0 T20 0", &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try expectVec(buf[1].quad.c, 5, 10);
    try expectVec(buf[1].quad.to, 10, 0);
    // reflection of (5,10) about (10,0) is (15,-10)
    try expectVec(buf[2].quad.c, 15, -10);
    try expectVec(buf[2].quad.to, 20, 0);
}

test "parse: arc" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 A5 5 0 0 1 10 0", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    const a = buf[1].arc;
    try std.testing.expectApproxEqAbs(@as(f32, 5), a.rx, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 5), a.ry, 1e-4);
    try std.testing.expectEqual(false, a.large_arc);
    try std.testing.expectEqual(true, a.sweep);
    try expectVec(a.to, 10, 0);
}

test "parse: arc flags may be adjacent" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 a5 5 0 0110 0", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    const a = buf[1].arc;
    try std.testing.expectEqual(false, a.large_arc);
    try std.testing.expectEqual(true, a.sweep);
    try expectVec(a.to, 10, 0);
}

test "parse: comma and implicit-minus separators" {
    var buf: [8]Cmd = undefined;
    var n = try parse("M0,0L10,10", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try expectVec(buf[1].line_to, 10, 10);

    n = try parse("M0 0L10-10", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try expectVec(buf[1].line_to, 10, -10);
}

test "parse: implicit decimal separator" {
    var buf: [8]Cmd = undefined;
    const n = try parse("M0 0 L1.5.5", &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try expectVec(buf[1].line_to, 1.5, 0.5);
}

test "parse: empty input yields zero commands" {
    var buf: [4]Cmd = undefined;
    try std.testing.expectEqual(@as(usize, 0), try parse("", &buf));
    try std.testing.expectEqual(@as(usize, 0), try parse("   ", &buf));
}

test "parse: out of space errors" {
    var buf: [1]Cmd = undefined;
    try std.testing.expectError(error.OutOfSpace, parse("M0 0 L10 10", &buf));
}

test "parse: invalid command errors" {
    var buf: [4]Cmd = undefined;
    try std.testing.expectError(error.InvalidPath, parse("X0 0", &buf));
    try std.testing.expectError(error.InvalidPath, parse("M", &buf));
}
