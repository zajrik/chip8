//! Handles app windowing and rendering.

const sdl3 = @import("sdl3");
const Color = sdl3.pixels.Color;
const Renderer = sdl3.render.Renderer;
const Window = sdl3.video.Window;

const bg_color: Color = .{ .r = 0, .g = 0, .b = 0 };
const fg_color: Color = .{ .r = 255, .g = 255, .b = 255 };

// =================================================================================================

const Display: type = @This();

window: Window,
renderer: Renderer,

/// Initialize a pre-configured `Display` instance on the stack.
pub fn init() !Display {
    const window, const renderer = try Renderer.initWithWindow(
        "chip-8",
        640,
        320,
        .{ .resizable = true },
    );

    errdefer renderer.deinit();
    errdefer window.deinit();

    try renderer.setLogicalPresentation(64, 32, .letter_box);

    return .{
        .window = window,
        .renderer = renderer,
    };
}

/// Deinitialize the `Display` instance.
pub fn deinit(self: Display) void {
    self.window.deinit();
    self.renderer.deinit();
}

/// Clear the display.
pub fn clear(self: Display) !void {
    try self.renderer.setDrawColor(bg_color);
    try self.renderer.clear();
}

/// Render the given buffer of pixels to the display.
pub fn render(self: Display, display_buffer: []u1) !void {
    try self.renderer.setDrawColor(fg_color);

    for (display_buffer, 0..) |bit, i| {
        if (bit == 1) try self.renderer.renderPoint(.{
            .x = @floatFromInt(i & 63),
            .y = @floatFromInt(i / 64),
        });
    }

    try self.renderer.present();
}
