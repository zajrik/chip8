const sdl3 = @import("sdl3");
const FramerateCapper = sdl3.extras.FramerateCapper;

const Display = @import("display.zig");
const Keys = @import("keys.zig");
const Machine = @import("machine.zig");
const Beep = @import("beep.zig");

// =================================================================================================

const AppState: type = @This();

/// Virtual machine instance
machine: Machine,

// Front-end modules
display: Display,
beep: Beep,

// Clock speed/tick management
clock: FramerateCapper(f32) = .{ .mode = .unlimited },
state_t: f32 = 0.0,
timer_t: f32 = 0.0,

/// Keys currently held down
keys: Keys = .empty,

/// Clean up resources owned by the app state.
pub fn deinit(self: AppState) void {
    self.display.deinit();
    self.beep.deinit();
}
