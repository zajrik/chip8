const std = @import("std");

const Keys = @import("keys.zig");
const Machine = @import("machine.zig");

const sdl3 = @import("sdl3");

const FramerateCapper = sdl3.extras.FramerateCapper;
const Renderer = sdl3.render.Renderer;
const Scancode = sdl3.Scancode;
const Window = sdl3.video.Window;

// =================================================================================================

fps: FramerateCapper(f32) = .{ .mode = .unlimited },

window: Window,
renderer: Renderer,

machine: Machine,

state_t: f32 = 0.0,
timer_t: f32 = 0.0,

keys: Keys = .empty,
