const std = @import("std");

// Minimal OpenGL 3.3 core function pointer table.
// Loaded at runtime via wglGetProcAddress / opengl32.dll.

pub const GLenum   = u32;
pub const GLuint   = u32;
pub const GLint    = i32;
pub const GLsizei  = i32;
pub const GLfloat  = f32;
pub const GLbitfield = u32;
pub const GLboolean  = u8;
pub const GLsizeiptr = isize;
pub const GLchar   = u8;

pub const ARRAY_BUFFER:        GLenum = 0x8892;
pub const STATIC_DRAW:         GLenum = 0x88B4;
pub const DYNAMIC_DRAW:        GLenum = 0x88E8;
pub const FLOAT:               GLenum = 0x1406;
pub const TRIANGLES:           GLenum = 0x0004;
pub const COLOR_BUFFER_BIT:    GLbitfield = 0x00004000;
pub const FRAGMENT_SHADER:     GLenum = 0x8B30;
pub const VERTEX_SHADER:       GLenum = 0x8B31;
pub const COMPILE_STATUS:      GLenum = 0x8B81;
pub const LINK_STATUS:         GLenum = 0x8B82;
pub const TEXTURE_2D:          GLenum = 0x0DE1;
pub const TEXTURE0:            GLenum = 0x84C0;
pub const TEXTURE_WRAP_S:      GLenum = 0x2802;
pub const TEXTURE_WRAP_T:      GLenum = 0x2803;
pub const TEXTURE_MIN_FILTER:  GLenum = 0x2801;
pub const TEXTURE_MAG_FILTER:  GLenum = 0x2800;
pub const NEAREST:             GLint  = 0x2600;
pub const CLAMP_TO_EDGE:       GLint  = 0x812F;
pub const RED:                 GLenum = 0x1903;
pub const R8:                  GLenum = 0x8229;
pub const UNSIGNED_BYTE:       GLenum = 0x1401;
pub const BLEND:               GLenum = 0x0BE2;
pub const SRC_ALPHA:           GLenum = 0x0302;
pub const ONE_MINUS_SRC_ALPHA: GLenum = 0x0303;
pub const UNPACK_ALIGNMENT:    GLenum = 0x0CF5;
pub const TRUE:  GLboolean = 1;
pub const FALSE: GLboolean = 0;
pub const INFO_LOG_LEN: GLenum = 0x8B84;

// Viewport / clear (from opengl32.dll, no extension loading needed)
extern "opengl32" fn glViewport(x: GLint, y: GLint, w: GLsizei, h: GLsizei) void;
extern "opengl32" fn glClearColor(r: GLfloat, g: GLfloat, b: GLfloat, a: GLfloat) void;
extern "opengl32" fn glClear(mask: GLbitfield) void;
extern "opengl32" fn glEnable(cap: GLenum) void;
extern "opengl32" fn glBlendFunc(sfactor: GLenum, dfactor: GLenum) void;
extern "opengl32" fn glPixelStorei(pname: GLenum, param: GLint) void;
extern "opengl32" fn glTexImage2D(target: GLenum, level: GLint, internalformat: GLint,
    width: GLsizei, height: GLsizei, border: GLint, format: GLenum, typ: GLenum,
    pixels: ?*const anyopaque) void;
extern "opengl32" fn glTexParameteri(target: GLenum, pname: GLenum, param: GLint) void;
extern "opengl32" fn glGenTextures(n: GLsizei, textures: [*]GLuint) void;
extern "opengl32" fn glBindTexture(target: GLenum, texture: GLuint) void;
extern "opengl32" fn glDeleteTextures(n: GLsizei, textures: [*]const GLuint) void;
// Re-export the simple functions directly so callers use gl.glViewport etc.
pub const viewport    = glViewport;
pub const clearColor  = glClearColor;
pub const clear       = glClear;
pub const enable      = glEnable;
pub const blendFunc   = glBlendFunc;
pub const pixelStorei = glPixelStorei;
pub const texImage2D  = glTexImage2D;
pub const texParameteri = glTexParameteri;
pub const genTextures   = glGenTextures;
pub const bindTexture   = glBindTexture;
pub const deleteTextures = glDeleteTextures;

// ── Extension function pointers (GL 3.3 core, loaded via wglGetProcAddress) ──

pub const Gl = struct {
    genVertexArrays:      *const fn (GLsizei, [*]GLuint) callconv(.c) void,
    bindVertexArray:      *const fn (GLuint) callconv(.c) void,
    deleteVertexArrays:   *const fn (GLsizei, [*]const GLuint) callconv(.c) void,
    genBuffers:           *const fn (GLsizei, [*]GLuint) callconv(.c) void,
    bindBuffer:           *const fn (GLenum, GLuint) callconv(.c) void,
    bufferData:           *const fn (GLenum, GLsizeiptr, ?*const anyopaque, GLenum) callconv(.c) void,
    deleteBuffers:        *const fn (GLsizei, [*]const GLuint) callconv(.c) void,
    enableVertexAttribArray: *const fn (GLuint) callconv(.c) void,
    vertexAttribPointer:  *const fn (GLuint, GLint, GLenum, GLboolean, GLsizei, ?*const anyopaque) callconv(.c) void,
    createShader:         *const fn (GLenum) callconv(.c) GLuint,
    shaderSource:         *const fn (GLuint, GLsizei, [*]const [*:0]const GLchar, ?[*]const GLint) callconv(.c) void,
    compileShader:        *const fn (GLuint) callconv(.c) void,
    getShaderiv:          *const fn (GLuint, GLenum, *GLint) callconv(.c) void,
    deleteShader:         *const fn (GLuint) callconv(.c) void,
    createProgram:        *const fn () callconv(.c) GLuint,
    attachShader:         *const fn (GLuint, GLuint) callconv(.c) void,
    linkProgram:          *const fn (GLuint) callconv(.c) void,
    getProgramiv:         *const fn (GLuint, GLenum, *GLint) callconv(.c) void,
    useProgram:           *const fn (GLuint) callconv(.c) void,
    deleteProgram:        *const fn (GLuint) callconv(.c) void,
    getUniformLocation:   *const fn (GLuint, [*:0]const GLchar) callconv(.c) GLint,
    uniform1i:            *const fn (GLint, GLint) callconv(.c) void,
    uniform2f:            *const fn (GLint, GLfloat, GLfloat) callconv(.c) void,
    drawArrays:           *const fn (GLenum, GLint, GLsizei) callconv(.c) void,
    activeTexture:        *const fn (GLenum) callconv(.c) void,

    pub fn load(getProcFn: fn ([*:0]const u8) ?*anyopaque) !Gl {
        const p = struct {
            fn get(getPf: fn ([*:0]const u8) ?*anyopaque, name: [*:0]const u8) *anyopaque {
                return getPf(name) orelse std.debug.panic("GL proc not found: {s}", .{name});
            }
        };
        return .{
            .genVertexArrays      = @ptrCast(@alignCast(p.get(getProcFn, "glGenVertexArrays"))),
            .bindVertexArray      = @ptrCast(@alignCast(p.get(getProcFn, "glBindVertexArray"))),
            .deleteVertexArrays   = @ptrCast(@alignCast(p.get(getProcFn, "glDeleteVertexArrays"))),
            .genBuffers           = @ptrCast(@alignCast(p.get(getProcFn, "glGenBuffers"))),
            .bindBuffer           = @ptrCast(@alignCast(p.get(getProcFn, "glBindBuffer"))),
            .bufferData           = @ptrCast(@alignCast(p.get(getProcFn, "glBufferData"))),
            .deleteBuffers        = @ptrCast(@alignCast(p.get(getProcFn, "glDeleteBuffers"))),
            .enableVertexAttribArray = @ptrCast(@alignCast(p.get(getProcFn, "glEnableVertexAttribArray"))),
            .vertexAttribPointer  = @ptrCast(@alignCast(p.get(getProcFn, "glVertexAttribPointer"))),
            .createShader         = @ptrCast(@alignCast(p.get(getProcFn, "glCreateShader"))),
            .shaderSource         = @ptrCast(@alignCast(p.get(getProcFn, "glShaderSource"))),
            .compileShader        = @ptrCast(@alignCast(p.get(getProcFn, "glCompileShader"))),
            .getShaderiv          = @ptrCast(@alignCast(p.get(getProcFn, "glGetShaderiv"))),
            .deleteShader         = @ptrCast(@alignCast(p.get(getProcFn, "glDeleteShader"))),
            .createProgram        = @ptrCast(@alignCast(p.get(getProcFn, "glCreateProgram"))),
            .attachShader         = @ptrCast(@alignCast(p.get(getProcFn, "glAttachShader"))),
            .linkProgram          = @ptrCast(@alignCast(p.get(getProcFn, "glLinkProgram"))),
            .getProgramiv         = @ptrCast(@alignCast(p.get(getProcFn, "glGetProgramiv"))),
            .useProgram           = @ptrCast(@alignCast(p.get(getProcFn, "glUseProgram"))),
            .deleteProgram        = @ptrCast(@alignCast(p.get(getProcFn, "glDeleteProgram"))),
            .getUniformLocation   = @ptrCast(@alignCast(p.get(getProcFn, "glGetUniformLocation"))),
            .uniform1i            = @ptrCast(@alignCast(p.get(getProcFn, "glUniform1i"))),
            .uniform2f            = @ptrCast(@alignCast(p.get(getProcFn, "glUniform2f"))),
            .drawArrays           = @ptrCast(@alignCast(p.get(getProcFn, "glDrawArrays"))),
            .activeTexture        = @ptrCast(@alignCast(p.get(getProcFn, "glActiveTexture"))),
        };
    }
};

pub fn cast(comptime T: type, ptr: ?*anyopaque) T {
    return @ptrCast(@alignCast(ptr orelse @panic("GL proc not found")));
}
