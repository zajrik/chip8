const std = @import("std");

const Writer = std.Io.Writer;

const expectEqual = std.testing.expectEqual;

// =================================================================================================

/// Represents a decoded 16-bit instruction.
pub const Instruction = packed struct(u16) {
    // /// Instruction category.
    // d: u4,

    // /// `VX` register or `N` operand.
    // x: u4,

    // /// `VY` register or `N` operand.
    // y: u4,

    // /// `N` operand, or part of `NN` / `NNN` operands.
    // n: u4,

    /// `N` operand, or part of `NN` / `NNN` operands.
    n: u4,

    /// `VY` register or `N` operand.
    y: u4,

    /// `VX` register or `N` operand.
    x: u4,

    /// Instruction category.
    d: u4,

    /// Decode the given 16-bit instruction.
    pub fn decode(instruction: u16) Instruction {
        // return .{
        //     .d = @intCast((instruction & 0xF000) >> 12),
        //     .x = @intCast((instruction & 0x0F00) >> 8),
        //     .y = @intCast((instruction & 0x00F0) >> 4),
        //     .n = @intCast(instruction & 0x000F),
        // };

        // If we reverse the order of the struct fields, we can just decode with
        // @bitCast, but I don't really like having them in reverse order, and also
        // I worry that it might be incorrect on different-endian systems, but that
        // may also be the case for decoding manually? 🤡
        //
        // Endianness confuses me. As I write this though, I realize we could order
        // them depending on endianness at comptime if that did indeed matter 🤔
        //
        // Gonna leave both here so I can switch between them for learning purposes
        //
        // Chip-8 reads its 16-bit instructions in big-endian order, I would assume
        // the zig compiler (and C, etc. compilers) would then take care of the byte
        // ordering for the system when doing the bitwise math to assemble them, but
        // I still don't know for sure how that would effect how zig handles bitcasting
        // the resulting 16-bit instruction to the packed struct fields in the order
        // it's requiring to represent the numbers as I'm encoding them.
        //
        // Why this order? Why male models?

        return @bitCast(instruction);
    }

    /// Returns the value of the `yn` byte of this instruction.
    pub fn nn(self: *const Instruction) u8 {
        return @as(u8, self.y) << 4 | self.n;
    }

    /// Returns the value of the `xyn` nibbles of this instruction.
    pub fn nnn(self: *const Instruction) u12 {
        return @as(u12, self.x) << 8 | @as(u8, self.y) << 4 | self.n;
    }

    /// Custom formatter for printing instructions for debugging.
    pub fn format(self: *const Instruction, writer: *Writer) !void {
        try writer.print(
            \\Instuction{{
            \\  .d = {},
            \\  .x = {},
            \\  .y = {},
            \\  .n = {},
            \\}}
        , .{ self.d, self.x, self.y, self.n });
    }
};

// =================================================================================================

test "instruction decoding" {
    const a: u16 = 0x1234;
    const i: Instruction = .decode(a);

    try expectEqual(0x0001, i.d);
    try expectEqual(0x0002, i.x);
    try expectEqual(0x0003, i.y);
    try expectEqual(0x0004, i.n);
    try expectEqual(0x0034, i.nn());
    try expectEqual(0x0234, i.nnn());
}
