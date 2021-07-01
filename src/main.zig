const std = @import("std");
const testing = std.testing;
const expect = std.testing.expect;

const c = @cImport({
    // See https://github.com/ziglang/zig/issues/515
    @cInclude("vlc_common.h");
    @cInclude("vlc_plugin.h");
    @cInclude("vlc_block.h");
    @cInclude("vlc_filter.h");
    @cInclude("vlc_aout.h");
});

// VLC Plugin API
pub const vlc_set_cb = fn (?*c_void, ?*c_void, c_int, ...) callconv(.C) c_int;

pub export fn vlc_entry__3_0_0f(maybe_vlc_set: ?vlc_set_cb, maybe_vlc: ?*c_void) c_int {
    vlc_entry_setup(maybe_vlc_set.?, maybe_vlc.?) catch return -1;
    return 0;
}

pub fn OpenFilterC(p_this: [*c]c.vlc_object_t) callconv(.C) c_int {
    // TODO use vlc logs
    const stdout = std.io.getStdOut().writer();

    if (OpenFilter(p_this)) |x| {
        return 0;
    } else |err| {
        stdout.print("error opening filter up {s}\n", .{err}) catch return -1;
        return -1;
    }
    return 0;
}

fn ConvertC(p_filter: [*c]c.filter_t, in_block: [*c]c.block_t) callconv(.C) [*c]c.block_t {
    const filter: *Filter = @ptrCast(*Filter, @alignCast(std.meta.alignment(*Filter), p_filter.*.p_sys));
    if (filter.Convert(in_block)) |out_block| {
        if (out_block != in_block) {
            filter.blockRelease(in_block);
        }
        return out_block;
    } else |err| {
        filter.blockRelease(in_block);
        return null;
    }
}

const Allocator = std.mem.Allocator;

const Filter = struct {
    allocator: *Allocator,

    fmt_in: c.es_format_t,
    fmt_out: c.es_format_t,

    audio_in: c.audio_format_t,
    audio_out: c.audio_format_t,

    channels_in: channels,
    channels_out: channels,
    channels_ratio: c_ulong,

    output_sample_size: u32,

    // mixer: anytype //fn(in: anytype, out: anytype) void,

    fn initPtr(allocator: *Allocator, fmt_in: c.es_format_t, fmt_out: c.es_format_t) !*Filter {
        const filter = try allocator.create(Filter);
        filter.allocator = allocator;
        filter.fmt_in = fmt_in;
        filter.fmt_out = fmt_out;

        filter.audio_in = fmt_in.unnamed_0.unnamed_0.audio;
        filter.audio_out = fmt_out.unnamed_0.unnamed_0.audio;

        filter.channels_in = channels.from_vlc_physical_channels(filter.audio_in.i_physical_channels);
        filter.channels_out = channels.from_vlc_physical_channels(filter.audio_out.i_physical_channels);

        filter.output_sample_size = @divTrunc(filter.audio_out.i_bitspersample * filter.audio_out.i_channels, 8);

        if (filter.output_sample_size == 0) {
            return error.FilterInitFailed;
        }

        filter.channels_ratio = @divTrunc(filter.channels_out.count(), filter.channels_in.count());

        // filter.mixer = mix2m;

        return filter;
    }

    fn Convert(self: *Filter, in_block: *c.block_t) ![*c]c.block_t {
        var out_block = try self.outputBlock(in_block);

        // const fmt2 = AudioBitFormat(channels{ .left = true, .right = true });
        // const src: [*]const fmt2 = @ptrCast([*]const fmt2, @alignCast(std.meta.alignment(fmt2), in_block.*.p_buffer));
        // var dst: [*]fmt2 = @ptrCast([*]fmt2, @alignCast(std.meta.alignment(fmt2), out_block.*.p_buffer));

        const src = mix2m.castSrc(in_block.*.p_buffer);
        var dst = mix2m.castDst(out_block.*.p_buffer);

        var i: u32 = 0;
        while (i < in_block.*.i_nb_samples) : (i += 1) {
            // try self.mixer(&src[i], &dst[i]);
            try mix2m.mix(&src[i], &dst[i]);
        }

        return out_block;
    }

    fn blockAlloc(self: *Filter, size: u32) ![*c]c.block_t {
        return c.block_Alloc(size);
    }

    fn blockRelease(self: *Filter, b: [*c]c.block_t) void {
        if (b != null) {
            c.block_Release(b);
        }
        return;
    }

    fn outputBlock(self: *Filter, in_block: [*c]c.block_t) ![*c]c.block_t {
        if (in_block == null or in_block.*.i_nb_samples == 0) {
            return null;
        }
        const out_size = in_block.*.i_nb_samples * self.output_sample_size;
        var out_block = try self.blockAlloc(out_size);

        out_block.*.i_nb_samples = in_block.*.i_nb_samples;
        out_block.*.i_dts = in_block.*.i_dts;
        out_block.*.i_pts = in_block.*.i_pts;
        out_block.*.i_length = in_block.*.i_length;

        out_block.*.i_nb_samples = in_block.*.i_nb_samples;

        out_block.*.i_buffer = in_block.*.i_buffer * self.channels_ratio;

        return out_block;
    }
};

fn Mixer(comptime SrcT: type, comptime DstT: type) type {
    return struct {
        const Self = @This();
        mix: fn (s: anytype, d: anytype) anyerror!void,

        fn castSrc(comptime _: Self, src: anytype) [*]const SrcT {
            return @ptrCast([*]const SrcT, @alignCast(std.meta.alignment(SrcT), src));
        }
        fn castDst(comptime _: Self, dst: anytype) [*]DstT {
            return @ptrCast([*]DstT, @alignCast(std.meta.alignment(DstT), dst));
        }
    };
}

const mix2m = Mixer(AudioBitFormat(channels{ .left = true, .right = true }), AudioBitFormat(channels{ .left = true, .right = true })){ .mix = mix2 };

fn mix2(in: anytype, out: anytype) !void {
    out.left = in.left;
    out.right = in.right;

    return;
}

const channels = packed struct {
    centre: bool = false,
    left: bool = false,
    right: bool = false,
    rear_centre: bool = false,
    rear_left: bool = false,
    rear_right: bool = false,
    middle_left: bool = false,
    middle_right: bool = false,
    lfe: bool = false,
    _: u7 = 0, // pack it out to u16

    const possibleChannels = 9;

    fn from_vlc_physical_channels(ch: u16) channels {
        return @bitCast(channels, ch);
    }

    fn audioBitFormat(ch: channels) type {
        return AudioBitFormat(ch);
    }

    fn count(ch: channels) u8 {
        return @popCount(u16, @bitCast(u16, ch));
    }

    fn get(self: channels, offset: usize, chData: []const f32) []const f32 {
        const channelCount = self.count();
        return chData[offset * channelCount .. (offset + 1) * channelCount];
    }

    fn set(self: channels, offset: usize, chData: []f32, in: []const f32) void {
        const channelCount = self.count();
        std.mem.copy(f32, chData[offset * channelCount .. (offset + 1) * channelCount], in[0..channelCount]);
        return;
    }
};

test "channels" {
    const ch = channels.from_vlc_physical_channels(c.AOUT_CHAN_LEFT);
    try expect(!ch.right);
    try expect(ch.left);
    try expect(ch.count() == 1);

    const ch2 = channels.from_vlc_physical_channels(c.AOUT_CHAN_LEFT | c.AOUT_CHAN_RIGHT);
    try expect(ch2.right);
    try expect(ch2.left);
    try expect(ch2.count() == 2);
}

const fmt2_0 = AudioBitFormat(channels{ .left = true, .right = true });

test "audio fmt" {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("hello {s}\n", .{fmt2_0});

    const f: fmt2_0 = .{ .left = @as(f32, 1), .right = @as(f32, 1) };

    try stdout.print("hello {s}\n", .{f});

    try expect(std.mem.eql(u8, @typeName(fmt2_0), "farts"));
}

fn AudioBitFormat(comptime ch: channels) type {
    var fields: [ch.count()]std.builtin.TypeInfo.StructField = undefined;
    var i = 0;

    const alignment = std.meta.alignment(f32);
    const default_value = @as(f32, 0);

    // TODO use @field
    if (ch.centre) {
        fields[i] = .{ .name = "centre", .field_type = f32, .default_value = default_value, .is_comptime = false, .alignment = alignment };
        i += 1;
    }
    if (ch.left) {
        fields[i] = .{ .name = "left", .field_type = f32, .default_value = default_value, .is_comptime = false, .alignment = alignment };
        i += 1;
    }
    if (ch.right) {
        fields[i] = .{ .name = "right", .field_type = f32, .default_value = default_value, .is_comptime = false, .alignment = alignment };
        i += 1;
    }

    const typeInfo = std.builtin.TypeInfo{ .Struct = .{
        .layout = std.builtin.TypeInfo.ContainerLayout.Packed,
        .fields = &fields,
        .decls = &[_]std.builtin.TypeInfo.Declaration{},
        .is_tuple = false,
    } };

    return @Type(typeInfo);
}

const VLC_CODEC_FL32: u32 = c.VLC_CODEC_FL32;

fn OpenFilter(p_this: [*]c.vlc_object_t) !void {
    const p_filter: [*c]c.filter_t = @ptrCast([*c]c.filter_t, @alignCast(std.meta.alignment(c.filter_t), p_this));

    const fmt_in = p_filter.*.fmt_in;
    const fmt_out = p_filter.*.fmt_out;

    var audio_in = fmt_in.unnamed_0.unnamed_0.audio;
    var audio_out = fmt_out.unnamed_0.unnamed_0.audio;

    if (audio_in.i_format != VLC_CODEC_FL32) {
        return error.VlcInitFailed;
    }
    if (audio_in.i_format != audio_out.i_format) {
        return error.VlcInitFailed;
    }
    if (audio_in.i_rate != audio_out.i_rate) {
        return error.VlcInitFailed;
    }

    var filter: *Filter = try Filter.initPtr(std.heap.c_allocator, fmt_in, fmt_out);

    p_filter.*.p_sys = @ptrCast(?*c.filter_sys_t, filter);
    p_filter.*.unnamed_0.pf_audio_filter = ConvertC;
}

fn vlc_entry_setup(vlc_set: vlc_set_cb, vlc_plugin: *c_void) !void {
    var module: *c.module_t = undefined;
    var config: *c.module_config_t = undefined;

    const m: struct {
        const Self = @This();
        vlc_plugin: *c_void,
        vlc_set: vlc_set_cb,
        module: *c.module_t = undefined,
        config: *c.module_config_t = undefined,

        fn init(self: Self) !void {
            return self.setOnPlugin(c.VLC_MODULE_CREATE, .{&self.module});
        }

        fn setOnPlugin(self: Self, comptime k: c_int, arg: anytype) !void {
            return self.set(k, null, arg);
        }

        fn setOnModule(self: Self, comptime k: c_int, arg: anytype) !void {
            return self.set(k, self.module, arg);
        }

        fn setOnConfig(self: Self, comptime k: c_int, arg: anytype) !void {
            return self.set(k, self.config, arg);
        }

        fn addTypeInner(self: Self, t: anytype) !void {
            return self.setOnPlugin(c.VLC_CONFIG_CREATE, .{ t, &self.config });
        }

        fn set(self: Self, comptime k: c_int, v: anytype, arg: anytype) !void {
            // until zig implements c vararg interop
            const rv = switch (arg.len) {
                1 => self.vlc_set(self.vlc_plugin, v, k, arg[0]),
                2 => self.vlc_set(self.vlc_plugin, v, k, arg[0], arg[1]),
                else => @compileError("unknown arg arity"),
            };

            if (rv != 0) {
                return error.VlcSetFailed;
            }
        }
    } = .{ .vlc_plugin = vlc_plugin, .vlc_set = vlc_set };

    try m.init();
    try m.setOnModule(c.VLC_MODULE_NAME, .{"panner"});
    try m.setOnModule(c.VLC_MODULE_DESCRIPTION, .{"audio channel panner / mixer"});
    try m.setOnModule(c.VLC_MODULE_CAPABILITY, .{"audio filter"});
    try m.setOnModule(c.VLC_MODULE_SCORE, .{@as(c_int, 1)});

    try m.addTypeInner(c.CONFIG_CATEGORY);
    try m.setOnConfig(c.VLC_CONFIG_VALUE, .{c.CAT_AUDIO});

    try m.addTypeInner(c.CONFIG_SUBCATEGORY);
    try m.setOnConfig(c.VLC_CONFIG_VALUE, .{c.SUBCAT_AUDIO_AFILTER});

    //var o = @ptrCast(?*c_void, OpenFilter);

    try m.setOnModule(c.VLC_MODULE_CB_OPEN, .{ "OpenFilter", OpenFilterC }); // @ptrCast(?*c_void, OpenFilter));
}
