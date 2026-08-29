const std = @import("std");

const Machine = @import("machine.zig");

pub fn main(init: std.process.Init) !void {
    const program = [_]u8{ 0xD0, 0x15 };

    var machine: Machine = .init(&program);
    machine.ir = 0x0050; // font sprite 0
    machine.v[0] = 60; // vx
    machine.v[1] = 27; // vy

    const op: u16 = machine.read();

    machine.execute(.decode(op));
    std.debug.print("{f}", .{&machine});

    _ = init;
}
