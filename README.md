# Zig OpenGL binding generator

## Usage

`build.zig`

    const opengl = b.dependency("opengl", .{
        .api = .gl,
        .major_version = 4,
        .minor_version = 6,
        .profile = .core,
        .extensions = "",
    });

    mod.addImport("gl", opengl.module("opengl"));

`main.zig`

    makeContextCurrent();
    try gl.load(getProcAddress);
    gl.clear(gl.COLOR_BUFFER_BIT);

A default copy of `gl.xml` is provided, as the upstream repository includes
unnecessary files. To use a different copy, set the `registry` build option.
