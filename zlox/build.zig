const std = @import("std");

pub fn build(b: *std.Build) void {
    // define executable
    const exe = b.addExecutable(.{
        .name = "lox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
        }),
    });

    // Custom Build options
    const options = b.addOptions();
    const debug_build = b.option(bool, "lox_debug", "enable debug features") orelse false;
    options.addOption(bool, "lox_debug", debug_build);

    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }
    const run_step = b.step("run", "Run lox");
    run_step.dependOn(&run_exe.step);

    // Testing
    const test_step = b.step("test", "unit tests");
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
        }),
    });
    unit_tests.root_module.addOptions("build_options", options);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    const exe_check = b.addExecutable(.{
        .name = "lox",
        .root_module = exe.root_module,
    });

    const check = b.step("check", "compile check without install");
    check.dependOn(&exe_check.step);

    // Debugger
    const lldb = b.addSystemCommand(&.{"lldb", "--"});
    lldb.addArtifactArg(unit_tests);
    const lldb_step = b.step("debug", "run lldb");
    lldb_step.dependOn(&lldb.step);
}
