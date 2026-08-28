const std = @import("std");
const Io = std.Io;

const expect = std.testing.expect;

const WIDTH = 64;
const HEIGHT = 32;

pub fn main(init: std.process.Init) !void {
    const program = [_]u8{ 0xD0, 0x15 };

    var machine: Machine = .init(&program);
    machine.ir = 0x0050; // font sprite 0
    machine.v[0] = 60; // vx
    machine.v[1] = 27; // vy

    const op: u16 = machine.read();

    machine.execute(Instruction.decode(op));
    std.debug.print("{s}", .{try machine.display(init.arena.allocator())});
}

const Machine = struct {
    ram: [4096]u8 = @splat(0x00),
    stack: Stack = .empty,
    v: [16]u8 = @splat(0x00),

    pc: u16 = 0x0200,
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

    /// Produce a string representation of the display buffer.
    pub fn display(self: *const Machine, alloc: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;

        for (self.display_buffer, 0..) |bit, i| {
            try out.print(alloc, "{}", .{bit});
            if (i + 1 & WIDTH - 1 == 0) try out.print(alloc, "\n", .{});
        }

        return out.toOwnedSlice(alloc);
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
                std.debug.print("Display op: {any}\n", .{op});
                const vx: u8 = self.v[op.x] & WIDTH - 1;
                const vy: u8 = self.v[op.y] & HEIGHT - 1;
                self.v[0xF] = 0x00;

                std.debug.print("Writing sprite at {}:{}\n", .{ vx, vy });

                for (0..op.n) |n| {
                    // Get sprite row byte from memory address in index register
                    const row: u8 = self.ram[self.ir + n];

                    // Write each byte of sprite row to display buffer
                    for (0..8) |i| {
                        // The display buffer pixel offset we're writing to
                        const offset: usize = vx + i + ((vy + n) * WIDTH);

                        // Which bit of the sprite row byte we're writing
                        const bit_index: u8 = @intCast(i);
                        const bit: u1 = @truncate(row >> @intCast(@as(u8, 7 - bit_index)));

                        // Skip off-pixels and pixels outside display bounds
                        if (bit != 1 or offset > WIDTH * HEIGHT or vx + i >= WIDTH) continue;

                        const current_bit: u1 = self.display_buffer[offset];
                        const new_bit: u1 = current_bit ^ bit;
                        self.display_buffer[offset] = new_bit;

                        // If the display pixel was toggled off, set flag register to 1
                        if (current_bit == 1 and new_bit == 0) self.v[0xF] = 0x01;
                    }
                }
            },

            0xE => {},
            0xF => {},
        }
    }
};

/// Represents a decoded 16-bit instruction.
const Instruction = packed struct(u16) {
    /// Instruction category.
    d: u4,

    /// VX register or N operand.
    x: u4,

    /// VY register or N operand.
    y: u4,

    /// Fourth nibble.
    n: u4,

    /// Decode the given 16-bit instruction.
    pub fn decode(instruction: u16) Instruction {
        return .{
            .d = @intCast((instruction & 0xF000) >> 12),
            .x = @intCast((instruction & 0x0F00) >> 8),
            .y = @intCast((instruction & 0x00F0) >> 4),
            .n = @intCast(instruction & 0x000F),
        };

        // If we reverse the order of the struct fields, we can just decode with
        // @bitCast, but I don't really like having them in reverse order, and also
        // I worry that it might be incorrect on different-endian systems, but that
        // may also be the case for decoding manually? 🤡
        //
        // Endianness confuses me. As I write this though, I realize we could order
        // them depending on endianness at comptime if that did indeed matter 🤔

        // return @bitCast(instruction);
    }

    /// Returns the value of the `yn` byte of this instruction.
    pub fn nn(self: *const Instruction) u8 {
        return @as(u8, self.y) << 4 | self.n;
    }

    /// Returns the value of the `xyn` nibbles of this instruction.
    pub fn nnn(self: *const Instruction) u12 {
        return @as(u12, self.x) << 8 | @as(u8, self.y) << 4 | self.n;
    }
};

test "instruction decoding" {
    const a: u16 = 0xBEEF;
    const i: Instruction = .decode(a);

    try expect(i.d == 0x000B);
    try expect(i.x == 0x000E);
    try expect(i.y == 0x000E);
    try expect(i.n == 0x000F);
    try expect(i.nn() == 0x00EE);
    try expect(i.nnn() == 0x0EEF);
}

/// Simple stack for holding 16-bit addresses.
const Stack = struct {
    arr: [256]u16 = @splat(0x00),
    ptr: u8 = 0x00,

    pub const empty: Stack = .{};

    pub fn push(self: *Stack, val: u16) void {
        defer self.ptr += 1;
        self.arr[self.ptr] = val;
    }

    pub fn pop(self: *Stack) u16 {
        self.ptr -= 1;
        return self.arr[self.ptr];
    }
};

/// Chip-8 font data.
const font: [80]u8 = .{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};
