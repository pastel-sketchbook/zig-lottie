const std = @import("std");

pub fn build(b: *std.Build) void {
    // ---------------------------------------------------------------
    // Native CLI executable
    // ---------------------------------------------------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("zig-lottie", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-lottie", .module = lib_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zig-lottie",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // `zig build run -- <args>`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Build and run the CLI");
    run_step.dependOn(&run_cmd.step);

    // ---------------------------------------------------------------
    // WASM library
    // ---------------------------------------------------------------
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = .ReleaseSmall,
    });

    const wasm_lib = b.addExecutable(.{
        .name = "zig-lottie",
        .root_module = wasm_mod,
    });
    wasm_lib.entry = .disabled;
    wasm_lib.rdynamic = true;

    const install_wasm = b.addInstallArtifact(wasm_lib, .{
        .dest_dir = .{ .override = .{ .custom = "wasm" } },
    });
    const wasm_step = b.step("wasm", "Build the WASM library");
    wasm_step.dependOn(&install_wasm.step);

    // ---------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------
    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_tests = b.addTest(.{
        .root_module = lib_test_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-lottie", .module = lib_mod },
        },
    });
    const exe_tests = b.addTest(.{
        .root_module = exe_test_mod,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
