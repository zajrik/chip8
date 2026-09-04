const std = @import("std");

const sdl3 = @import("sdl3");
const Audio = sdl3.mixer.Audio;
const FramerateCapper = sdl3.extras.FramerateCapper;
const Mixer = sdl3.mixer.Mixer;
const Renderer = sdl3.render.Renderer;
const Scancode = sdl3.Scancode;
const Track = sdl3.mixer.Track;
const Window = sdl3.video.Window;

const Keys = @import("keys.zig");
const Machine = @import("machine.zig");

// =================================================================================================

fps: FramerateCapper(f32) = .{ .mode = .unlimited },

// Display stuff
window: Window,
renderer: Renderer,

// Sound stuff
mixer: Mixer,
tone: Audio,
beep: Track,

// Virtual machine instance
machine: Machine,

// Timer tick tracking
state_t: f32 = 0.0,
timer_t: f32 = 0.0,

// Keys currently held down
keys: Keys = .empty,
