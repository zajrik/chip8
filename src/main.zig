const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = std.Io.Dir;
const Prng = std.Random.DefaultPrng;
const sys_clock = Io.Clock.real;

const sdl3 = @import("sdl3");
const AppResult = sdl3.AppResult;
const Event = sdl3.events.Event;
const Init = sdl3.Init;
const InitFlags = sdl3.InitFlags;

const AppState = @import("app_state.zig");
const Display = @import("display.zig");
const Machine = @import("machine.zig");
const Beep = @import("beep.zig");

comptime {
    _ = sdl3.main_callbacks;
}
pub const _start = void;
pub const WinMainCRTStartup = void;

const flags: InitFlags = .{ .video = true, .audio = true, .events = true };

const machine_ticks_per_second: f32 = 1.0 / 600.0;
const timer_ticks_per_second: f32 = 1.0 / 60.0;

// =================================================================================================

pub fn init(sdl_init: Init) !struct { AppState, AppResult } {
    try sdl3.init(flags);
    errdefer sdl3.quit(flags);

    try sdl3.mixer.init();
    errdefer sdl3.mixer.quit();

    // Initialize display module
    const display: Display = try .init();
    errdefer display.deinit();

    // Initialize beep module (for beeping)
    const beep: Beep = try .init();
    errdefer beep.deinit();

    // Read program from disk
    // const program = @import("data/test_program.zig").program;
    const program: []u8 = try readFile(
        sdl_init.arena.allocator(),
        sdl_init.io,
        "rom/test_opcode.ch8",
    );

    var prng: Prng = initPrng(sdl_init.io);

    return .{
        .{
            .machine = .init(program[0..], &prng),
            .display = display,
            .beep = beep,
        },
        .run,
    };
}

pub fn iterate(state: *AppState) !AppResult {
    const dt: f32 = state.clock.delay();

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

    // Update display
    try state.display.clear();
    try state.display.render(&state.machine.display_buffer);

    // Start/stop beep depending on machine sound timer
    switch (state.machine.sound) {
        0 => if (!state.keys.hasScancode(.b)) try state.beep.stop(),
        else => if (!state.beep.isBeeping()) try state.beep.start(),
    }

    return .run;
}

pub fn event(state: *AppState, ev: Event) !AppResult {
    switch (ev) {
        .quit, .terminating => return .success,

        .key_down => |it| if (it.scancode) |s| {
            state.keys.add(s);

            // Play beep when 'b' is pressed
            if (s == .b and !state.beep.isBeeping()) {
                try state.beep.start();
            }
        },

        .key_up => |it| if (it.scancode) |s| state.keys.remove(s),

        else => {},
    }

    return .run;
}

pub fn quit(state: ?*AppState, _: AppResult) void {
    if (state) |it| it.deinit();

    sdl3.mixer.quit();
    sdl3.quit(flags);
    sdl3.shutdown();
}

// =================================================================================================

/// Initialize an `std.Random.DefaultPrng` instance seeded with the current time.
fn initPrng(io: Io) Prng {
    return .init(@bitCast(sys_clock.now(io).toMicroseconds()));
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
