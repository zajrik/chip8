//! Simple stack for holding 16-bit addresses.
const Stack: type = @This();

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
