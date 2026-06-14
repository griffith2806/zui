const build_options = @import("build_options");

pub const Renderer = switch (build_options.backend) {
    .software => @import("software/renderer.zig").Renderer,
    .opengl   => @import("opengl/renderer.zig").Renderer,
    .vulkan   => @import("vulkan/renderer.zig").Renderer,
};
