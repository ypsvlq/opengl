const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "opengl-generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const registry = b.option(std.Build.LazyPath, "registry", "Path to OpenGL registry") orelse b.path("src/gl.xml");
    const api = b.option(enum { gl, gles1, gles2, glsc2 }, "api", "Target API") orelse .gl;
    const major_version = b.option(u8, "major_version", "Target major API version") orelse 1;
    const minor_version = b.option(u8, "minor_version", "Target minor API version") orelse 0;
    const profile = b.option(enum { compatibility, core }, "profile", "Target profile") orelse .compatibility;
    const maybe_extensions = b.option([]const u8, "extensions", "Extensions to enable");

    const generate_cmd = b.addRunArtifact(exe);
    generate_cmd.addFileArg(registry);
    const generated_file = generate_cmd.addOutputFileArg("gl.zig");
    generate_cmd.addArg(@tagName(api));
    generate_cmd.addArg(b.fmt("{}.{}", .{ major_version, minor_version }));
    generate_cmd.addArg(@tagName(profile));
    if (maybe_extensions) |extensions| {
        const wf = b.addWriteFiles();
        const extensions_file = wf.add("extensions.txt", extensions);
        generate_cmd.addFileArg(extensions_file);
    }

    _ = b.addModule("opengl", .{ .root_source_file = generated_file });

    const gl_zig_install = b.addInstallFile(generated_file, "gl.zig");
    b.getInstallStep().dependOn(&gl_zig_install.step);
}
