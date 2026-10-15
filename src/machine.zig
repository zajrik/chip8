//! Virtual machine for interpreting CHIP-8 instructions.

const std = @import("std");

const Random = std.Random;
const Writer = std.Io.Writer;

const Instruction = @import("instruction.zig").Instruction;
const Keys = @import("keys.zig");
const Stack = @import("stack.zig");

const assert = std.debug.assert;

const font: [80]u8 = @import("data/font.zig").font;

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

/// Index register. CHIP-8 only uses 12 bits for addresses.
ir: u16 = 0x0000,

delay: u8 = 0x00,
sound: u8 = 0x00,

display_buffer: [WIDTH * HEIGHT]u1 = @splat(0b0),

/// Indicates keys that were held down on the previous machine tick.
previous_keys: Keys = .empty,

/// Indicates keys that are held down on the current machine tick.
keys: Keys = .empty,

/// `std.Random` instance for generating random numbers.
rand: Random,

// =================================================================================================

/// Initialize a `Machine` instance on the stack.
pub fn init(program: []const u8, prng: *Random.DefaultPrng) Machine {
    var self: Machine = .{ .rand = prng.random() };

    // Copy font into memory at the conventional address
    @memcpy(self.ram[0x0050..0x00A0], &font);

    // Copy program into memory at the conventional address
    @memcpy(self.ram[0x0200..][0..program.len], program);

    return self;
}

/// Fetch/decode/execute next instruction.
pub fn tick(self: *Machine, keys: Keys) void {
    self.previous_keys = self.keys;
    self.keys = keys;

    const op: u16 = self.read();
    self.execute(.decode(op));
}

/// Decrement timers.
pub fn tickTimers(self: *Machine) void {
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

/// Execute the given instruction.
pub fn execute(self: *Machine, op: Instruction) void {
    // Unpack instruction
    const d: u4 = op.d;
    const x: u4 = op.x;
    const y: u4 = op.y;
    const n: u4 = op.n;
    const nn: u8 = op.nn();
    const nnn: u12 = op.nnn();

    // Dispatch instruction.
    //
    // Instructions are grouped/ordered by functionality where applicable at the
    // cost of not necessarily being ordered numerically
    switch (d) {
        0x0 => switch (nnn) {
            // 0x00E0: Clear display buffer
            0x0E0 => self.display_buffer = @splat(0b0),
            // 0x00EE: Return from subroutine
            0x0EE => self.pc = self.stack.pop(),

            else => unreachable,
        },

        // 0x1NNN: Jump to NNN
        0x1 => self.pc = nnn,

        // 0xBNNN: Jump to NNN + V0 offset
        // CHIP-48/SUPER-CHIP changed this behavior to PC = XNN + VX, may want config
        // option to support that changed behavior
        0xB => self.pc = nnn + self.v[0],

        // 0x2NNN: Call subroutine at NNN
        0x2 => {
            self.stack.push(self.pc);
            self.pc = nnn;
        },

        // Skip instructions:
        // - 0x3XNN: Skip next instruction if VX == NN
        // - 0x4XNN: Skip next instruction if VX != NN
        // - 0x5XY0: Skip next instruction if VX == VY
        // - 0x9XY0: Skip next instruction if VX != VY
        0x3, 0x4, 0x5, 0x9 => {
            const vx: u8 = self.v[x];
            const vy: u8 = self.v[y];

            if (d == 0x5 or d == 0x9) assert(n == 0);

            const res: bool = switch (d) {
                0x3 => vx == nn,
                0x4 => vx != nn,
                0x5 => vx == vy,
                0x9 => vx != vy,
                else => unreachable,
            };

            self.pc += @as(u16, 2) * @intFromBool(res);
        },

        // Skip instructions:
        // 0xEX9E: Skip next instruction if key in VX is down
        // 0xEXA1: Skip next instruction if key in VX is up
        0xE => {
            const vx: u8 = self.v[x];
            switch (nn) {
                0x9E => self.pc += @as(u16, 2) * @intFromBool(self.keys.has(vx)),
                0xA1 => self.pc += @as(u16, 2) * @intFromBool(!self.keys.has(vx)),

                else => unreachable,
            }
        },

        // 0x6XNN: Set register VX to NN
        0x6 => self.v[x] = nn,

        // 0x7XNN: Add NN to register VX. Overflows but does not set carry flag.
        0x7 => self.v[x] +%= nn,

        // 0x8XYN: Logical/arithmetic instructions
        0x8 => switch (n) {
            // 0x8XY0: Set VX to value of VY
            0x0 => self.v[x] = self.v[y],

            // 0x8XY1: Set VX to VX | VY
            0x1 => self.v[x] |= self.v[y],

            // 0x8XY2: Set VX to VX & VY
            0x2 => self.v[x] &= self.v[y],

            // 0x8XY3: Set VX to VX ^ VY
            0x3 => self.v[x] ^= self.v[y],

            // 0x8XY4: Set VX to VX + VY
            0x4 => {
                const vx: u8 = self.v[x];
                const vy: u8 = self.v[y];

                self.v[x] = vx +% vy;
                self.v[0xF] = @intFromBool(@as(u16, vx) + vy > 0xFF);
            },

            // 0x8XY5, 0x8XY7: Set VX to VX - VY (N == 5) or VY - VX (N == 7)
            0x5, 0x7 => {
                const vx: u8 = self.v[x];
                const vy: u8 = self.v[y];

                const min: u8, const sub: u8 = switch (n) {
                    0x5 => .{ vx, vy },
                    0x7 => .{ vy, vx },
                    else => unreachable,
                };

                self.v[x] = min -% sub;
                self.v[0xF] = @intFromBool(min >= sub);
            },

            // 0x8XY6, 0x8XYE: Set VX to VX >> 1 (N == 6) or VX << 1 (N == E)
            // These instructions were changed for CHIP-48/SUPER-CHIP to the above behavior.
            // Old behavior copied VY into VX and then shifted VX. May want to allow config
            // to support the old behavior
            0x6, 0xE => {
                const vx: u8 = self.v[x];

                const res: u9, const ovf: u1 = switch (n) {
                    0x6 => .{ vx >> 1, @intFromBool(vx & 0x01 != 0) },
                    0xE => .{ vx << 1, @intFromBool(vx & 0x80 != 0) },
                    else => unreachable,
                };

                self.v[x] = @truncate(res);
                self.v[0xF] = ovf;
            },

            else => unreachable,
        },

        // 0xANNN: Set index register to NNN
        0xA => self.ir = nnn,

        // 0xCXNN: Set VX to rand & NN
        0xC => self.v[x] = self.rand.int(u8) & nn,

        // 0xDXYN: Draw sprite from memory location pointed to by the index register
        0xD => {
            const vx: u8 = self.v[x] & WIDTH - 1;
            const vy: u8 = self.v[y] & HEIGHT - 1;
            self.v[0xF] = 0x00;

            // Slice sprite bytes from memory
            const sprite: []u8 = self.ram[self.ir..][0..n];

            // Write sprite bytes to display buffer. For each bit of a row's byte
            // value, toggle the corresponding pixel in the display buffer.
            //
            // If a pixel was turned off, set the flag register (VF) to 1, otherwise 0

            for (sprite, 0..) |byte, bn| for (0..8) |i| {
                const bit: u1 = @truncate(byte >> @intCast(7 - i));

                // The offset of the display buffer pixel we're writing
                const offset: usize = vx + i + (vy + bn) * WIDTH;

                if (bit != 1 or offset >= WIDTH * HEIGHT or vx + i >= WIDTH) continue;

                const old_bit: u1 = self.display_buffer[offset];
                const new_bit: u1 = old_bit ^ bit;
                self.display_buffer[offset] = new_bit;

                if (old_bit == 1 and new_bit == 0) self.v[0xF] = 0x01;
            };
        },

        // FX instructions. These don't really line up with other instructions 💀
        0xF => {
            const vx: u8 = self.v[x];

            switch (nn) {
                // 0xFX07: Set VX to the value of the delay timer
                0x07 => self.v[x] = self.delay,

                // 0xFX15: Set delay timer to the value of VX
                0x15 => self.delay = vx,

                // 0xFX18: Set the sound timer to the value of VX
                0x18 => self.sound = vx,

                // 0xFX0A: Block execution until a key is released, set VX to that key
                0x0A => {
                    const released: Keys = self.previous_keys.diff(self.keys);

                    if (released.first()) |key| {
                        self.v[x] = key;
                    } else {
                        self.pc -= 2;
                    }
                },

                // 0xFX1E: Set I += VX, set VF = 1 on overflow
                0x1E => {
                    const i: u16 = self.ir;
                    self.ir = (i + vx) & 0xFFF;
                    self.v[0xF] = @intFromBool(i + vx > 0xFFF);
                },

                // 0xFX29: Set I to the index of the font sprite for VX
                // Only takes the second nibble of the byte in VX
                0x29 => self.ir = 0x050 + (vx & 0x0F) * 5,

                // 0xFX33: Store separate decimal digits of VX in ram at $I..$I+2
                0x33 => {
                    self.ram[self.ir] = vx / 100;
                    self.ram[self.ir + 1] = vx % 100 / 10;
                    self.ram[self.ir + 2] = vx % 100 % 10;
                },

                // 0xFX55: Store registers V0..VX at $I..$I+X
                0x55 => @memcpy(
                    self.ram[self.ir..][0 .. @as(usize, x) + 1],
                    self.v[0 .. @as(usize, x) + 1],
                ),

                // 0xFX65: Load registers V0..VX from $I..$I+X
                0x65 => @memcpy(
                    self.v[0 .. @as(usize, x) + 1],
                    self.ram[self.ir..][0 .. @as(usize, x) + 1],
                ),

                else => unreachable,
            }
        },
    }
}

/// Custom formatter for printing display buffer for debugging.
pub fn format(self: *const Machine, writer: *Writer) !void {
    for (self.display_buffer, 0..) |bit, i| {
        try writer.print("{s}", .{if (bit == 1) "#" else " "});
        try writer.writeAll(if (i + 1 & WIDTH - 1 == 0) "\n" else "|");
    }
}
