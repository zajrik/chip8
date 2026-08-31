const std = @import("std");

const Machine = @import("machine.zig");

const Io = std.Io;
const Prng = std.Random.DefaultPrng;

const clock = Io.Clock.real;

pub fn main(init: std.process.Init) !void {
    var prng: Prng = initPrng(init.io);

    const program = [_]u8{
        0xA0, 0x50, // Set I = 0x050 (sprite 0)
        0x60, 0x02, // Set V0 = 0x02
        0x61, 0x01, // Set V1 = 0x01
        0xD0, 0x15, // Draw VX = V0, VY = V1, N = 5
        0xA0, 0x55, // Set I = 0x055 (sprite 1)
        0x70, 0x05, // Add V0 += 0x05
        0xD0, 0x15, // Draw VX = V0, VY = V1, N = 5
        0xC2, 0xFF, // Set V2 = rand & 0xFF
    };

    var machine: Machine = .init(&program, &prng);
    for (0..program.len / 2) |_| machine.execute(.decode(machine.read()));

    std.debug.print("{f}\n", .{&machine});
    std.debug.print("{}", .{machine.v[2]});
}

/// Initialize an `std.Random.DefaultPrng` instance seeded with the current time.
fn initPrng(io: Io) Prng {
    return .init(@bitCast(clock.now(io).toMicroseconds()));
}
