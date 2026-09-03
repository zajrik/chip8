const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = std.Io.Dir;
const Prng = std.Random.DefaultPrng;

const AppState = @import("app_state.zig");
const Machine = @import("machine.zig");

const sdl3 = @import("sdl3");

const AppResult = sdl3.AppResult;
const Color = sdl3.pixels.Color;
const Event = sdl3.events.Event;
const Init = sdl3.Init;
const InitFlags = sdl3.InitFlags;
const Renderer = sdl3.render.Renderer;
const Window = sdl3.video.Window;

const clock = Io.Clock.real;

comptime {
    _ = sdl3.main_callbacks;
}
pub const _start = void;
pub const WinMainCRTStartup = void;

const flags: InitFlags = .{ .video = true, .events = true };
const bg_color: Color = .{ .r = 0, .g = 0, .b = 0 };
const fg_color: Color = .{ .r = 255, .g = 255, .b = 255 };

const machine_ticks_per_second: f32 = 1.0 / 600.0;
const timer_ticks_per_second: f32 = 1.0 / 60.0;

// =================================================================================================

pub fn init(sdl_init: Init) !struct { AppState, AppResult } {
    try sdl3.init(flags);
    errdefer sdl3.quit(flags);

    const window: Window, const renderer: Renderer = try Renderer.initWithWindow(
        "chip-8",
        640,
        320,
        .{ .resizable = true },
    );

    errdefer renderer.deinit();
    errdefer window.deinit();

    try renderer.setLogicalPresentation(64, 32, .letter_box);

    // const program = @import("data/test_program.zig").program;
    const program: []u8 = try readFile(
        sdl_init.arena.allocator(),
        sdl_init.io,
        "rom/test_opcode.ch8",
    );

    var prng: Prng = initPrng(sdl_init.io);

    return .{
        .{
            .window = window,
            .renderer = renderer,
            .machine = .init(program[0..], &prng),
        },
        .run,
    };
}

pub fn iterate(state: *AppState) !AppResult {
    const dt: f32 = state.fps.delay();

    state.state_t += dt;
    state.timer_t += dt;

    // Tick machine at configured rate
    while (state.state_t >= machine_ticks_per_second) {
        state.state_t -= machine_ticks_per_second;
        state.machine.tick(state.keys);
    }

    // Tick timers at configured rate
    while (state.timer_t >= timer_ticks_per_second) {
        state.timer_t -= timer_ticks_per_second;
        state.machine.tickTimers();
    }

    // Clear display
    try state.renderer.setDrawColor(bg_color);
    try state.renderer.clear();

    // Render display buffer
    try state.renderer.setDrawColor(fg_color);
    for (state.machine.display_buffer, 0..) |bit, i| {
        if (bit == 1) try state.renderer.renderPoint(.{
            .x = @floatFromInt(i & 63),
            .y = @floatFromInt(i / 64),
        });
    }
    try state.renderer.present();

    return .run;
}

pub fn event(state: *AppState, ev: Event) !AppResult {
    return switch (ev) {
        .quit => .success,
        .terminating => .success,

        .key_down => |it| {
            if (it.scancode) |s| state.keys.add(s);
            return .run;
        },

        .key_up => |it| {
            if (it.scancode) |s| state.keys.remove(s);
            return .run;
        },

        else => .run,
    };
}

pub fn quit(state: ?*AppState, result: AppResult) void {
    _ = result;

    if (state) |it| {
        it.window.deinit();
        it.renderer.deinit();
    }

    sdl3.quit(flags);
    sdl3.shutdown();
}

// =================================================================================================

/// Initialize an `std.Random.DefaultPrng` instance seeded with the current time.
fn initPrng(io: Io) Prng {
    return .init(@bitCast(clock.now(io).toMicroseconds()));
}

/// Read the contents of the file at the given `path` using the given `Io` implementation.
///
/// Returns a slice containing the characters in the file. The caller owns this
/// slice and is responsible for freeing it.
pub fn readFile(alloc: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Dir.readFileAlloc(
        Dir.cwd(),
        io,
        path,
        alloc,
        .unlimited,
    );
}
