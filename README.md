# Zig OpenGL binding generator

## Usage

In your build script:

```zig
const opengl = b.dependency("opengl", .{
    .registry = null, // use vendored gl.xml
    .api = .gl,
    .major_version = 3,
    .minor_version = 2,
    .profile = .core,
    .extensions = "KHR_debug",
    .thread_local = false,
});

mod.addImport("gl", opengl.module("opengl"));
```

In your program:

```zig
makeContextCurrent();
try gl.load(getProcAddress);

gl.clear(gl.COLOR_BUFFER_BIT);

if (gl.extensions.KHR_debug) {
    gl.debugMessageCallback(debugCallback, null);
}
```
