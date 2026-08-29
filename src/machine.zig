//! Virtual machine for interpreting Chip-8 instructions.

const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const Stack = @import("stack.zig");

const Writer = std.Io.Writer;

const assert = std.debug.assert;

const font: [80]u8 = @import("font.zig").font;

// Dimensions must be powers of 2 to allow using `n & WIDTH - 1` over `n % width` for
// supporting chip-8's VX/VY wrapping behavior. Binary AND is much faster than modulo

const WIDTH = 64;
const HEIGHT = 32;

comptime {
    assert(std.math.isPowerOfTwo(WIDTH));
    assert(std.math.isPowerOfTwo(HEIGHT));
}

// =================================================================================================

const Machine: type = @This();

ram: [4096]u8 = @splat(0x00),
stack: Stack = .empty,

/// Variable registers, V0 through VF.
v: [16]u8 = @splat(0x00),

/// Program counter, pointing to the next instruction to read.
pc: u16 = 0x0200,

/// Index register
ir: u16 = 0x0000,

delay: u8 = 0x00,
sound: u8 = 0x00,

display_buffer: [WIDTH * HEIGHT]u1 = @splat(0b0),

pub fn init(program: []const u8) Machine {
    var self: Machine = .{};

    // Copy font into memory at the conventional address
    @memcpy(self.ram[0x0050..0x00A0], &font);

    // Copy program into memory at the conventional address
    @memcpy(self.ram[0x0200..(0x0200 + program.len)], program);

    return self;
}

/// Decrement counters.
pub fn tick(self: *Machine) void {
    self.delay -|= 1;
    self.sound -|= 1;
}

/// Read the next instruction opcode from memory, incrementing the program counter.
pub fn read(self: *Machine) u16 {
    defer self.pc +|= 2;
    const byte_1: u8 = self.ram[self.pc];
    const byte_2: u8 = self.ram[self.pc + 1];
    return @as(u16, byte_1) << 8 | byte_2;
}

/// Custom formatter for printing display buffer for debugging.
pub fn format(self: *const Machine, writer: *Writer) !void {
    for (self.display_buffer, 0..) |bit, i| {
        try writer.print("{}", .{bit});
        if (i + 1 & WIDTH - 1 == 0) try writer.writeAll("\n");
    }
}

/// Execute the given instruction.
pub fn execute(self: *Machine, op: Instruction) void {
    switch (op.d) {
        0x0 => switch (op) {
            // 0x00E0: Clear display buffer
            comptime Instruction.decode(0x00E0) => self.display_buffer = @splat(0b0),
            // 0x00EE: Return from subroutine
            comptime Instruction.decode(0x00EE) => self.pc = self.stack.pop(),

            else => unreachable,
        },

        // 0x1NNN: Jump to NNN
        0x1 => self.pc = op.nnn(),

        // 0x2NNN: Call subroutine at NNN
        0x2 => {
            self.stack.push(self.pc);
            self.pc = op.nnn();
        },

        0x3 => {},
        0x4 => {},
        0x5 => {},

        // 0x6XNN: Set register VX to NN
        0x6 => self.v[op.x] = op.nn(),

        // 0x7XNN: Add NN to register VX. Does not overflow.
        0x7 => self.v[op.x] +|= op.nn(),

        0x8 => {},
        0x9 => {},

        // 0xANNN: Set index register to NNN
        0xA => self.ir = op.nnn(),

        0xB => {},
        0xC => {},

        // 0xDXYN: Draw sprite from memory location pointed to by the index register
        0xD => {
            const vx: u8 = self.v[op.x] & WIDTH - 1;
            const vy: u8 = self.v[op.y] & HEIGHT - 1;
            self.v[0xF] = 0x00;

            std.debug.print("Display op: {f}\n", .{op});
            std.debug.print("VX = {}, VY = {}\n", .{ vx, vy });

            // Slice sprite rows from memory
            const sprite_rows: []u8 = self.ram[self.ir..(self.ir + op.n)];

            // Write sprite row bytes to display buffer. For each bit of a row's
            // byte value, toggle the corresponding pixel in the display buffer.
            //
            // If a pixel was turned off, set the flag register (VF) to 1, otherwise 0

            for (sprite_rows, 0..) |row, n| for (0..8) |i| {
                const bit_index: u8 = @intCast(i);
                const bit: u1 = @truncate(row >> @intCast(@as(u8, 7 - bit_index)));

                // The offset of the display buffer pixel we're writing
                const offset: usize = vx + i + ((vy + n) * WIDTH);

                if (bit != 1 or offset > WIDTH * HEIGHT or vx + i >= WIDTH) continue;

                const current_bit: u1 = self.display_buffer[offset];
                const new_bit: u1 = current_bit ^ bit;
                self.display_buffer[offset] = new_bit;

                if (current_bit == 1 and new_bit == 0) self.v[0xF] = 0x01;
            };
        },

        0xE => {},
        0xF => {},
    }
}
