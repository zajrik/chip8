//! Holds bits representing keys that are currently held down.

const sdl3 = @import("sdl3");

const Scancode = sdl3.Scancode;

/// Bitflag representing any unused key.
const invalid_key: u32 = 0x80000000;

/// Bitflags representing key flags reserved for the emulator.
const app_keys: u32 = 0x7FFF0000;

/// Bitflags representing valid CHIP-8 keys (`0` through `F`).
const chip8_keys: u32 = 0x0000FFFF;

// =================================================================================================

const Keys: type = @This();

/// Bitfield representing held keys.
value: u32 = 0x00000000,

/// `Keys` instance with no held keys.
pub const empty: Keys = .{};

// =================================================================================================

/// Add the given `key` to this `Keys`.
pub fn add(self: *Keys, key: Scancode) void {
    self.value |= codeFlag(key);
}

/// Remove the given `key` from this `Keys`.
pub fn remove(self: *Keys, key: Scancode) void {
    self.value &= ~codeFlag(key);
}

/// Returns a `Keys` indicating the keys that are down in `self` but not `other`.
pub fn diff(self: Keys, other: Keys) Keys {
    return .{ .value = self.value & ~other.value };
}

/// Returns the first CHIP-8 key in this `Keys` that is down, or `null` if
/// no CHIP-8 keys are down.
///
/// Keys are checked iteratively in order from `0` to `F`.
pub fn first(self: Keys) ?u8 {
    return for (0..16) |i| {
        const key: u5 = @truncate(i);

        if ((self.value >> key) & 0x01 == 1) {
            break key;
        }
    } else null;
}

/// Returns whether the given CHIP-8 `key` (`0` through `F`) is currently held down.
pub fn isDown(self: Keys, key: u8) bool {
    return self.value & keyFlag(key) != 0;
}

/// Returns whether any CHIP-8 key (`0` through `F`) is currently held down.
pub fn isAnyDown(self: Keys) bool {
    return self.value & chip8_keys > 0;
}

/// Returns whether the given `key` is currently held down (by scancode).
pub fn isDownByScancode(self: Keys, key: Scancode) bool {
    return self.value & codeFlag(key) != 0;
}

// =================================================================================================

/// Converts the given `key` (CHIP-8 key `0` through `F`) to a bitflag integer.
fn keyFlag(key: u8) u32 {
    return @as(u32, 1) << @as(u5, @truncate(key));
}

/// Converts the given sdl3 scancode to a bitflag integer.
///
/// Unsupported scancodes always return `0x80000000`.
fn codeFlag(key: Scancode) u32 {
    return @as(u32, 1) << keyIndex(key);
}

/// Map the given `key` to a bit index for bitfield storage.
fn keyIndex(key: Scancode) u5 {
    return switch (key) {
        .one => 0x01,
        .two => 0x02,
        .three => 0x03,
        .four => 0x0C,

        .q => 0x04,
        .w => 0x05,
        .e => 0x06,
        .r => 0x0D,

        .a => 0x07,
        .s => 0x08,
        .d => 0x09,
        .f => 0x0E,

        .z => 0x0A,
        .x => 0x00,
        .c => 0x0B,
        .v => 0x0F,

        inline else => 0x1F,
    };
}
