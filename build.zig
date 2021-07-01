const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("panner_plugin", "src/main.zig", b.version(0, 0, 1));
    lib.setBuildMode(mode);
    lib.linkLibC();
    lib.addIncludeDir("src/vlc/include");
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.linkLibC();
    main_tests.addIncludeDir("src/vlc/include");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
