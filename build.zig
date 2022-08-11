const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("guzzler", "source/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.install();

    const raylib = @import("raylib/build.zig");
    exe.addPackage(raylib.raylib_pkg);
    exe.linkLibrary(raylib.getRaylib(b, mode, target));
    exe.addPackage(raylib.raygui_pkg);
    exe.linkLibrary(raylib.getRaygui(b, mode, target));

    const nfd = @import("nfd-zig/build.zig");
    exe.linkLibrary(nfd.makeLib(b, mode, target, "nfd-zig/") catch unreachable);
    exe.addPackage(std.build.Pkg{
        .name = "nfd",
        .source = .{ .path = "nfd-zig/src/lib.zig" },
    });

    const run_step = exe.run();
    if (b.args) |args| run_step.addArgs(args);
    run_step.step.dependOn(b.getInstallStep());
    b.step("run", "Run the game").dependOn(&run_step.step);
}
