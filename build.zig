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

    const registry = b.option(std.Build.LazyPath, "registry", "Path to OpenGL registry (default: built-in)") orelse b.path("src/gl.xml");
    const api = b.option(enum { gl, gles1, gles2, glsc2 }, "api", "Target API (default: gl)") orelse .gl;
    const major_version = b.option(u8, "major_version", "Target major API version (default: 1)") orelse 1;
    const minor_version = b.option(u8, "minor_version", "Target minor API version (default: 0)") orelse 0;
    const profile = b.option(enum { compatibility, core }, "profile", "Target profile (default: compatibility)") orelse .compatibility;
    const extensions = b.option([]const u8, "extensions", "Extensions to enable (default: none)") orelse "";
    const thread_local = b.option(bool, "thread_local", "Use threadlocal variables for context state (default: false)") orelse false;

    const generate_cmd = b.addRunArtifact(exe);
    generate_cmd.addFileArg(registry);
    const generated_file = generate_cmd.addOutputFileArg("gl.zig");
    generate_cmd.addArg(@tagName(api));
    generate_cmd.addArg(b.fmt("{}.{}", .{ major_version, minor_version }));
    generate_cmd.addArg(@tagName(profile));
    generate_cmd.addFileArg(b.addWriteFiles().add("extensions.txt", extensions));
    generate_cmd.addArg(if (thread_local) "true" else "false");

    _ = b.addModule("opengl", .{ .root_source_file = generated_file });

    const gl_zig_install = b.addInstallFile(generated_file, "gl.zig");
    b.getInstallStep().dependOn(&gl_zig_install.step);
}
