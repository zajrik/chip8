//! Plays a beep sound on-demand.

const sdl3 = @import("sdl3");
const Audio = sdl3.mixer.Audio;
const Mixer = sdl3.mixer.Mixer;
const Track = sdl3.mixer.Track;

// =================================================================================================

const Beep: type = @This();

mixer: Mixer,
tone: Audio,
beep: Track,

/// Initialize a `Beep` instance on the stack.
pub fn init() !Beep {
    const mixer: Mixer = try .initDevice(.default_playback, null);
    errdefer mixer.deinit();

    const tone: Audio = try .initSineWaveAudio(mixer, 1400, 1.0, null);
    errdefer tone.deinit();

    const beep: Track = try .init(mixer);
    errdefer beep.deinit();

    try beep.setAudio(tone);

    return .{
        .mixer = mixer,
        .tone = tone,
        .beep = beep,
    };
}

/// Deinitialize this `Beep` instance.
pub fn deinit(self: Beep) void {
    self.beep.deinit();
    self.tone.deinit();
    self.mixer.deinit();
}

/// Returns whether this `Beep` instance is beeping.
pub fn isBeeping(self: Beep) bool {
    return self.beep.isPlaying();
}

/// Begin playing beep sound.
pub fn start(self: Beep) !void {
    try self.beep.play(.{});
}

/// Stop playing beep sound.
pub fn stop(self: Beep) !void {
    try self.beep.stop(0);
}
