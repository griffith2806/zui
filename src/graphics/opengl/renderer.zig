const std   = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;
const gl    = @import("gl.zig");
const atlas = @import("font_atlas.zig");
const GlContext = @import("../../platform/win32/gl_context.zig").GlContext;

// ── Shaders ──────────────────────────────────────────────────────────────────

const VERT_SRC: [*:0]const u8 =
    \\#version 330 core
    \\layout(location=0) in vec2 pos;
    \\layout(location=1) in vec2 uv;
    \\layout(location=2) in vec4 color;
    \\out vec2 v_uv;
    \\out vec4 v_color;
    \\uniform vec2 u_screen;
    \\void main() {
    \\    v_uv   = uv;
    \\    v_color = color;
    \\    vec2 ndc = vec2(pos.x / u_screen.x * 2.0 - 1.0,
    \\                    1.0 - pos.y / u_screen.y * 2.0);
    \\    gl_Position = vec4(ndc, 0.0, 1.0);
    \\}
;

const FRAG_SRC: [*:0]const u8 =
    \\#version 330 core
    \\in vec2 v_uv;
    \\in vec4 v_color;
    \\out vec4 frag;
    \\uniform sampler2D u_tex;
    \\void main() {
    \\    if (v_uv.x < 0.0) {
    \\        frag = v_color;
    \\    } else {
    \\        float a = texture(u_tex, v_uv).r;
    \\        frag = vec4(v_color.rgb, v_color.a * a);
    \\    }
    \\}
;

// ── Rounded-rect SDF shaders ─────────────────────────────────────────────────
// Separate program: draws a single quad with a signed-distance-field frag test.
// Flush the batch first, draw with uniforms, then resume batching.

const VERT_ROUND: [*:0]const u8 =
    \\#version 330 core
    \\layout(location=0) in vec2 pos;
    \\uniform vec2 u_screen;
    \\void main() {
    \\    vec2 ndc = vec2(pos.x / u_screen.x * 2.0 - 1.0,
    \\                    1.0 - pos.y / u_screen.y * 2.0);
    \\    gl_Position = vec4(ndc, 0.0, 1.0);
    \\}
;

const FRAG_ROUND: [*:0]const u8 =
    \\#version 330 core
    \\out vec4 frag;
    \\uniform vec4  u_rect;
    \\uniform float u_radius;
    \\uniform vec4  u_color;
    \\uniform vec2  u_screen;
    \\float roundedBoxSDF(vec2 p, vec2 b, float r) {
    \\    return length(max(abs(p) - b + r, 0.0)) - r;
    \\}
    \\void main() {
    \\    vec2 fc = vec2(gl_FragCoord.x, u_screen.y - gl_FragCoord.y);
    \\    vec2 center = vec2(u_rect.x + u_rect.z * 0.5, u_rect.y + u_rect.w * 0.5);
    \\    float dist = roundedBoxSDF(fc - center, vec2(u_rect.z, u_rect.w) * 0.5, u_radius);
    \\    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    \\    frag = vec4(u_color.rgb, u_color.a * alpha);
    \\}
;

// ── Vertex layout: [x,y, u,v, r,g,b,a]  (8 floats per vertex) ───────────────
const FLOATS_PER_VERT: usize = 8;
const VERTS_PER_QUAD:  usize = 6; // 2 triangles
const MAX_QUADS:       usize = 4096;
const MAX_VERTS:       usize = MAX_QUADS * VERTS_PER_QUAD;

pub const Renderer = struct {
    ctx:        GlContext,
    gl_fns:     gl.Gl,
    prog:       gl.GLuint,
    vao:        gl.GLuint,
    vbo:        gl.GLuint,
    tex_white:  gl.GLuint,
    tex_font:   gl.GLuint,
    u_screen:   gl.GLint,
    u_tex:      gl.GLint,
    // Rounded-rect SDF program
    prog_round:    gl.GLuint,
    vao_round:     gl.GLuint,
    vbo_round:     gl.GLuint,
    u_rnd_screen:  gl.GLint,
    u_rnd_rect:    gl.GLint,
    u_rnd_radius:  gl.GLint,
    u_rnd_color:   gl.GLint,
    width:      u32,
    height:     u32,
    buf:        [MAX_VERTS * FLOATS_PER_VERT]f32 = undefined,
    vert_count: usize = 0,

    pub fn init(hwnd: anytype, width: u32, height: u32) !Renderer {
        var ctx = try GlContext.create(@ptrCast(hwnd));
        errdefer ctx.deinit();

        const g = try gl.Gl.load(GlContext.getProcAddress);

        // ── Shader ────────────────────────────────────────────────────────────
        const prog = try compileProgram(g);

        // ── VAO + VBO ─────────────────────────────────────────────────────────
        var vao: gl.GLuint = 0;
        var vbo: gl.GLuint = 0;
        g.genVertexArrays(1, @as(*[1]gl.GLuint, &vao));
        g.genBuffers(1, @as(*[1]gl.GLuint, &vbo));
        g.bindVertexArray(vao);
        g.bindBuffer(gl.ARRAY_BUFFER, vbo);
        g.bufferData(gl.ARRAY_BUFFER, MAX_VERTS * FLOATS_PER_VERT * @sizeOf(f32), null, gl.DYNAMIC_DRAW);

        const stride: gl.GLsizei = @intCast(FLOATS_PER_VERT * @sizeOf(f32));
        g.enableVertexAttribArray(0);
        g.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(0));
        g.enableVertexAttribArray(1);
        g.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));
        g.enableVertexAttribArray(2);
        g.vertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
        g.bindVertexArray(0);

        // ── 1×1 white texture ─────────────────────────────────────────────────
        var tex_white: gl.GLuint = 0;
        gl.genTextures(1, @as(*[1]gl.GLuint, &tex_white));
        gl.bindTexture(gl.TEXTURE_2D, tex_white);
        const white: [1]u8 = .{255};
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.texImage2D(gl.TEXTURE_2D, 0, @intCast(gl.R8), 1, 1, 0, gl.RED, gl.UNSIGNED_BYTE, &white);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

        // ── Font atlas texture ────────────────────────────────────────────────
        var atlas_data: [atlas.ATLAS_H][atlas.ATLAS_W]u8 = undefined;
        atlas.build(&atlas_data);

        var tex_font: gl.GLuint = 0;
        gl.genTextures(1, @as(*[1]gl.GLuint, &tex_font));
        gl.bindTexture(gl.TEXTURE_2D, tex_font);
        gl.texImage2D(gl.TEXTURE_2D, 0, @intCast(gl.R8),
            @intCast(atlas.ATLAS_W), @intCast(atlas.ATLAS_H), 0,
            gl.RED, gl.UNSIGNED_BYTE, &atlas_data[0][0]);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        // ── Rounded-rect SDF program ──────────────────────────────────────────
        const prog_round = try compileProgram2(g, VERT_ROUND, FRAG_ROUND);

        var vao_round: gl.GLuint = 0;
        var vbo_round: gl.GLuint = 0;
        g.genVertexArrays(1, @as(*[1]gl.GLuint, &vao_round));
        g.genBuffers(1, @as(*[1]gl.GLuint, &vbo_round));
        g.bindVertexArray(vao_round);
        g.bindBuffer(gl.ARRAY_BUFFER, vbo_round);
        g.bufferData(gl.ARRAY_BUFFER, 6 * 2 * @sizeOf(f32), null, gl.DYNAMIC_DRAW);
        g.enableVertexAttribArray(0);
        g.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), @ptrFromInt(0));
        g.bindVertexArray(0);

        g.useProgram(prog_round);
        const u_rnd_screen = g.getUniformLocation(prog_round, "u_screen");
        const u_rnd_rect   = g.getUniformLocation(prog_round, "u_rect");
        const u_rnd_radius = g.getUniformLocation(prog_round, "u_radius");
        const u_rnd_color  = g.getUniformLocation(prog_round, "u_color");

        // ── State ─────────────────────────────────────────────────────────────
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        g.useProgram(prog);
        const u_screen = g.getUniformLocation(prog, "u_screen");
        const u_tex    = g.getUniformLocation(prog, "u_tex");
        g.uniform1i(u_tex, 0);

        gl.viewport(0, 0, @intCast(width), @intCast(height));

        return .{
            .ctx          = ctx,
            .gl_fns       = g,
            .prog         = prog,
            .vao          = vao,
            .vbo          = vbo,
            .tex_white    = tex_white,
            .tex_font     = tex_font,
            .u_screen     = u_screen,
            .u_tex        = u_tex,
            .prog_round   = prog_round,
            .vao_round    = vao_round,
            .vbo_round    = vbo_round,
            .u_rnd_screen = u_rnd_screen,
            .u_rnd_rect   = u_rnd_rect,
            .u_rnd_radius = u_rnd_radius,
            .u_rnd_color  = u_rnd_color,
            .width        = width,
            .height       = height,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.gl_fns.deleteProgram(self.prog);
        self.gl_fns.deleteProgram(self.prog_round);
        self.gl_fns.deleteBuffers(1, @as(*[1]gl.GLuint, &self.vbo));
        self.gl_fns.deleteBuffers(1, @as(*[1]gl.GLuint, &self.vbo_round));
        self.gl_fns.deleteVertexArrays(1, @as(*[1]gl.GLuint, &self.vao));
        self.gl_fns.deleteVertexArrays(1, @as(*[1]gl.GLuint, &self.vao_round));
        gl.deleteTextures(1, @as(*[1]gl.GLuint, &self.tex_white));
        gl.deleteTextures(1, @as(*[1]gl.GLuint, &self.tex_font));
        self.ctx.deinit();
    }

    pub fn clear(self: *Renderer, color: Color) void {
        const f = color.toF32();
        gl.clearColor(f[0], f[1], f[2], f[3]);
        gl.clear(gl.COLOR_BUFFER_BIT);
        self.vert_count = 0;
    }

    pub fn fillRect(self: *Renderer, rect: Rect, color: Color) void {
        self.pushQuad(rect, .{ 0, 0, 0, 0 }, color, false);
    }

    pub fn drawText(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color) void {
        for (text, 0..) |ch, i| {
            const gx = x + @as(i32, @intCast(i * atlas.GLYPH_W));
            const gr = Rect.init(gx, y, atlas.GLYPH_W, atlas.GLYPH_H);
            self.pushQuad(gr, atlas.glyphUV(ch), color, true);
        }
    }

    pub fn textWidth(text: []const u8) u32 {
        return @intCast(text.len * atlas.GLYPH_W);
    }

    pub fn drawTextScaled(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        const s: i32 = @intCast(scale);
        const gw: i32 = @intCast(atlas.GLYPH_W);
        const gh: i32 = @intCast(atlas.GLYPH_H);
        for (text, 0..) |ch, i| {
            const gx = x + @as(i32, @intCast(i)) * gw * s;
            const gr = Rect.init(gx, y, @intCast(gw * s), @intCast(gh * s));
            self.pushQuad(gr, atlas.glyphUV(ch), color, true);
        }
    }

    pub fn textWidthScaled(text: []const u8, scale: u32) u32 {
        return @intCast(text.len * atlas.GLYPH_W * scale);
    }

    /// Draw a filled rounded rectangle using an SDF fragment shader.
    /// Flushes the batch first so mixing with fillRect is safe.
    pub fn fillRoundRect(self: *Renderer, rect: Rect, radius: u32, color: Color) void {
        self.flush();
        const g = &self.gl_fns;

        const x0: f32 = @floatFromInt(rect.x);
        const y0: f32 = @floatFromInt(rect.y);
        const x1: f32 = @floatFromInt(rect.right());
        const y1: f32 = @floatFromInt(rect.bottom());
        const quad = [6][2]f32{
            .{ x0, y0 }, .{ x1, y0 }, .{ x1, y1 },
            .{ x0, y0 }, .{ x1, y1 }, .{ x0, y1 },
        };

        g.useProgram(self.prog_round);
        g.uniform2f(self.u_rnd_screen, @floatFromInt(self.width), @floatFromInt(self.height));
        g.uniform4f(self.u_rnd_rect, x0, y0, @floatFromInt(rect.width), @floatFromInt(rect.height));
        g.uniform1f(self.u_rnd_radius, @floatFromInt(radius));
        const cf = color.toF32();
        g.uniform4f(self.u_rnd_color, cf[0], cf[1], cf[2], cf[3]);

        g.bindVertexArray(self.vao_round);
        g.bindBuffer(gl.ARRAY_BUFFER, self.vbo_round);
        g.bufferData(gl.ARRAY_BUFFER, @sizeOf([6][2]f32), &quad[0][0], gl.DYNAMIC_DRAW);
        g.drawArrays(gl.TRIANGLES, 0, 6);
        g.bindVertexArray(0);

        // Restore main batch program
        g.useProgram(self.prog);
        g.uniform2f(self.u_screen, @floatFromInt(self.width), @floatFromInt(self.height));
    }

    pub fn present(self: *Renderer) void {
        self.flush();
        self.ctx.swapBuffers();
    }

    fn flush(self: *Renderer) void {
        if (self.vert_count == 0) return;
        const g = &self.gl_fns;

        g.useProgram(self.prog);
        g.uniform2f(self.u_screen, @floatFromInt(self.width), @floatFromInt(self.height));

        g.bindVertexArray(self.vao);
        g.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        g.bufferData(gl.ARRAY_BUFFER,
            @intCast(self.vert_count * FLOATS_PER_VERT * @sizeOf(f32)),
            &self.buf[0], gl.DYNAMIC_DRAW);

        g.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.tex_font); // both solid+text use font tex; white solid handled via u_use_tex=0
        g.drawArrays(gl.TRIANGLES, 0, @intCast(self.vert_count));
        g.bindVertexArray(0);

        self.vert_count = 0;
    }

    fn pushQuad(self: *Renderer, rect: Rect, uv: [4]f32, color: Color, use_tex: bool) void {
        if (self.vert_count + VERTS_PER_QUAD > MAX_VERTS) self.flush();

        const x0: f32 = @floatFromInt(rect.x);
        const y0: f32 = @floatFromInt(rect.y);
        const x1: f32 = @floatFromInt(rect.x + @as(i32, @intCast(rect.width)));
        const y1: f32 = @floatFromInt(rect.y + @as(i32, @intCast(rect.height)));
        const ul = uv[0]; const vt = uv[1];
        const ur = uv[2]; const vb = uv[3];
        const cf = color.toF32();
        const r = cf[0]; const g_c = cf[1]; const b = cf[2]; const a = cf[3];

        const use_f: f32 = if (use_tex) 1.0 else 0.0;
        _ = use_f;

        // Encode use_tex in the UV: for solid rects we pass u=0,v=0 and sample white tex.
        // The shader checks u_use_tex uniform... but we batch mixed quads so we need to
        // split flush on texture change. Simpler: use a per-vertex flag encoded in UV.
        // We use u_use_tex as 0.0 (solid) or 1.0 (text) packed into v coordinate sign.
        // Actually simplest: solid rects use the white texture (0,0 UV) and tex sampling
        // on a white texel = 1.0 → same as solid. Switch to WHITE texture for solid pass.

        // We'll use a different approach: push a solid-color pass marker via UV=(−1,−1).
        // The fragment shader: if (v_uv.x < 0.0) use solid color, else sample atlas.
        const s_ul = if (use_tex) ul else -1.0;
        const s_ur = if (use_tex) ur else -1.0;
        const s_vt = if (use_tex) vt else -1.0;
        const s_vb = if (use_tex) vb else -1.0;

        const base = self.vert_count * FLOATS_PER_VERT;
        const verts = [VERTS_PER_QUAD][FLOATS_PER_VERT]f32{
            .{ x0, y0, s_ul, s_vt, r, g_c, b, a },
            .{ x1, y0, s_ur, s_vt, r, g_c, b, a },
            .{ x1, y1, s_ur, s_vb, r, g_c, b, a },
            .{ x0, y0, s_ul, s_vt, r, g_c, b, a },
            .{ x1, y1, s_ur, s_vb, r, g_c, b, a },
            .{ x0, y1, s_ul, s_vb, r, g_c, b, a },
        };
        for (verts, 0..) |v, vi| {
            @memcpy(self.buf[base + vi * FLOATS_PER_VERT ..][0..FLOATS_PER_VERT], &v);
        }
        self.vert_count += VERTS_PER_QUAD;
    }
};

fn compileProgram(g: gl.Gl) !gl.GLuint {
    return compileProgram2(g, VERT_SRC, FRAG_SRC);
}

fn compileProgram2(g: gl.Gl, vert: [*:0]const u8, frag: [*:0]const u8) !gl.GLuint {
    const vs = g.createShader(gl.VERTEX_SHADER);
    g.shaderSource(vs, 1, @as(*const [1][*:0]const gl.GLchar, &vert), null);
    g.compileShader(vs);
    var ok: gl.GLint = 0;
    g.getShaderiv(vs, gl.COMPILE_STATUS, &ok);
    if (ok == 0) return error.VertexShaderCompileFailed;

    const fs = g.createShader(gl.FRAGMENT_SHADER);
    g.shaderSource(fs, 1, @as(*const [1][*:0]const gl.GLchar, &frag), null);
    g.compileShader(fs);
    g.getShaderiv(fs, gl.COMPILE_STATUS, &ok);
    if (ok == 0) return error.FragmentShaderCompileFailed;

    const prog = g.createProgram();
    g.attachShader(prog, vs);
    g.attachShader(prog, fs);
    g.linkProgram(prog);
    g.getProgramiv(prog, gl.LINK_STATUS, &ok);
    g.deleteShader(vs);
    g.deleteShader(fs);
    if (ok == 0) return error.ProgramLinkFailed;
    return prog;
}
