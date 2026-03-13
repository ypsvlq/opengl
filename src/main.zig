const std = @import("std");
const xml = @import("xml.zig");
const Registry = @import("Registry.zig");
const Api = @import("Api.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const xml_path = args.next() orelse return error.MissingArgument;
    const out_path = args.next() orelse return error.MissingArgument;
    const api = args.next() orelse return error.MissingArgument;
    const version = args.next() orelse return error.MissingArgument;
    const profile = args.next() orelse return error.MissingArgument;
    const extensions_path = args.next();

    var extensions: std.ArrayList([]const u8) = .empty;
    if (extensions_path) |path| {
        const data = try readFile(allocator, path);
        var iter = std.mem.tokenizeAny(u8, data, &std.ascii.whitespace);
        while (iter.next()) |name| {
            try extensions.append(allocator, name);
        }
    }

    const registry_bytes = try readFile(allocator, xml_path);
    const registry = try Registry.init(allocator, registry_bytes);

    const output = try std.fs.cwd().createFile(out_path, .{});
    defer output.close();
    var buffer: [4096]u8 = undefined;
    var writer = output.writer(&buffer);

    try generate(
        allocator,
        &writer.interface,
        registry,
        .{ .api = api, .version = version, .profile = profile },
        extensions.items,
    );

    try writer.interface.flush();
}

fn generate(allocator: std.mem.Allocator, writer: *std.Io.Writer, registry: Registry, target: Api.Target, extensions: [][]const u8) !void {
    const api = try Api.init(allocator, registry, target, extensions);
    const enums = api.enums.keys();

    const commands, const types = blk: {
        var commands: std.ArrayList([]const u8) = .empty;
        var types: std.StringArrayHashMapUnmanaged(void) = .empty;

        var command_iter = api.commands.keyIterator();
        while (command_iter.next()) |key_ptr| {
            const name = key_ptr.*;
            const command = registry.command_map.get(name).?;

            var list = std.Io.Writer.Allocating.init(allocator);
            try list.writer.print("{c}{s}: ?*const fn (", .{ std.ascii.toLower(name[2]), name[3..] });

            var param_iter = command.findChildrenByTag("param");
            var comma = false;
            while (param_iter.next()) |param| {
                try list.writer.print("{s}{s}_: ", .{ if (comma) ", " else "", param.getCharData("name").? });
                comma = true;
                if (try writeType(&list.writer, param)) |ptype| {
                    try types.put(allocator, ptype, {});
                }
            }

            try list.writer.writeAll(") callconv(APIENTRY) ");

            if (try writeType(&list.writer, command.findChildByTag("proto").?)) |ptype| {
                try types.put(allocator, ptype, {});
            }

            try commands.append(allocator, list.toArrayList().items);
        }
        break :blk .{ commands.items, types.keys() };
    };

    std.mem.sort([]const u8, types, {}, stringLessThan);
    std.mem.sort([]const u8, enums, {}, stringLessThan);
    std.mem.sort([]const u8, extensions, {}, stringLessThan);
    std.mem.sort([]const u8, commands, {}, stringLessThan);

    try writer.writeAll(
        \\const std = @import("std");
        \\const builtin = @import("builtin");
        \\pub const APIENTRY: std.builtin.CallingConvention = if (builtin.os.tag == .windows) .winapi else .c;
        \\pub fn load(getProcAddress: anytype) !void {
        \\    @setEvalBranchQuota(100000);
        \\    const function_names = comptime blk: {
        \\        const fields = @typeInfo(@TypeOf(functions)).@"struct".fields;
        \\        var names: [fields.len][*:0]const u8 = undefined;
        \\        for (&names, fields) |*name, field| name.* = "gl" ++ &[_]u8{std.ascii.toUpper(field.name[0])} ++ field.name[1..];
        \\        break :blk names;
        \\    };
        \\    const function_pointers: *[function_names.len]?*const anyopaque = @ptrCast(&functions);
        \\    for (function_pointers, function_names) |*pointer, name| {
        \\        pointer.* = @ptrCast(getProcAddress(name));
        \\    }
        \\
    );
    if (extensions.len > 0) {
        try writer.writeAll(
            \\    const extension_names = comptime blk: {
            \\        const fields = @typeInfo(@TypeOf(extensions)).@"struct".fields;
            \\        var names: [fields.len][]const u8 = undefined;
            \\        for (&names, fields) |*name, field| name.* = "GL_" ++ field.name;
            \\        break :blk names;
            \\    };
            \\    const extension_flags: *[extension_names.len]bool = @ptrCast(&extensions);
            \\
        );
        if (api.commands.contains("glGetStringi")) {
            try writer.writeAll(
                \\    var num_extensions: i32 = undefined;
                \\    getIntegerv(NUM_EXTENSIONS, &num_extensions);
                \\    var i: u32 = 0;
                \\    while (i < num_extensions) : (i += 1) {
                \\        const extension = std.mem.sliceTo(getStringi(EXTENSIONS, i), 0);
                \\        for (extension_flags, extension_names) |*flag, name| {
                \\            if (std.mem.eql(u8, name, extension)) {
                \\                flag.* = true;
                \\                break;
                \\            }
                \\        }
                \\    }
                \\
            );
        } else {
            try writer.writeAll(
                \\    const extension_string = std.mem.sliceTo(getString(EXTENSIONS), 0);
                \\    for (extension_flags, extension_names) |*flag, name| {
                \\        if (std.mem.indexOf(u8, extension_string, name)) |index| {
                \\            if (index == 0 or index + name.len == extension_string.len or (extension_string[index - 1] == ' ' and extension_string[index + name.len] == ' ')) {
                \\                flag.* = true;
                \\            }
                \\        }
                \\    }
                \\
            );
        }
    }
    try writer.writeAll("}\n");

    for (types) |name| {
        if (!rewrite_types.has(name)) {
            try writer.writeAll("pub const ");
            try writeTypeName(writer, name);
            try writer.print(" = {s};\n", .{alias_types.get(name).?});
        }
    }

    for (enums) |name| {
        try writer.print("pub const {f} = {s};\n", .{ std.zig.fmtId(name[3..]), registry.enum_map.get(name).? });
    }

    if (extensions.len > 0) {
        try writer.writeAll("pub var extensions: extern struct {\n");
        for (extensions) |name| {
            try writer.print("    {f}: bool = false,\n", .{std.zig.fmtId(name[3..])});
        }
        try writer.writeAll("} = .{};\n");
    }

    try writer.writeAll("pub var functions: extern struct {\n");
    for (commands) |command| {
        try writer.print("    {s} = null,\n", .{command});
    }
    try writer.writeAll(
        \\} = .{};
        \\
    );

    for (commands) |command| {
        const colon = std.mem.indexOfScalar(u8, command, ':').?;
        const param_start = std.mem.indexOfScalar(u8, command, '(').?;
        const param_end = std.mem.indexOfScalar(u8, command, ')').?;
        const callconv_end = std.mem.lastIndexOfScalar(u8, command, ')').?;

        try writer.print("pub fn {s}{s}{s} {{\n    return functions.{s}.?(", .{ command[0..colon], command[param_start .. param_end + 1], command[callconv_end + 1 ..], command[0..colon] });

        var param_iter = std.mem.splitAny(u8, command[param_start + 1 .. param_end], ":,");
        var comma = false;
        while (param_iter.next()) |name| {
            try writer.print("{s}{s}", .{ if (comma) "," else "", name });
            _ = param_iter.next();
            comma = true;
        }

        try writer.writeAll(");\n}\n");
    }
}

fn writeType(writer: *std.Io.Writer, element: *xml.Element) !?[]const u8 {
    const maybe_ptype = element.getCharData("ptype");

    const is_opaque = if (maybe_ptype) |ptype| std.mem.startsWith(u8, ptype, "struct ") else false;
    const replacements = [_][2][]const u8{
        .{ "const void *", "?*const anyopaque" },
        .{ "void *", "?*anyopaque" },
        .{ "*", if (is_opaque) "?*" else "[*c]" },
        .{ "const", "const " },
        .{ "void", "void" },
        .{ " ", "" },
    };
    var iter = std.mem.reverseIterator(element.children);
    while (iter.next()) |child| {
        var data = if (child == .char_data) child.char_data else continue;
        var old_data_len = data.len;
        while (data.len > 0) {
            for (replacements) |replacement| {
                if (std.mem.endsWith(u8, data, replacement[0])) {
                    try writer.writeAll(replacement[1]);
                    data.len -= replacement[0].len;
                }
            }
            if (data.len == old_data_len) {
                return error.UnknownType;
            }
            old_data_len = data.len;
        }
    }

    if (maybe_ptype) |ptype| {
        if (rewrite_types.get(ptype)) |name| {
            try writer.writeAll(name);
        } else {
            try writeTypeName(writer, ptype);
        }
    }

    return maybe_ptype;
}

fn writeTypeName(writer: *std.Io.Writer, name: []const u8) !void {
    if (!std.mem.startsWith(u8, name, "GL")) {
        if (std.mem.startsWith(u8, name, "struct ")) {
            try writer.writeAll(name[7..]);
            return;
        }
        return error.UnknownType;
    }

    if (std.mem.eql(u8, name, "GLsizei")) {
        try writer.writeAll("SizeI");
    } else if (std.mem.startsWith(u8, name, "GLclamp")) {
        try writer.print("Clamp{c}", .{std.ascii.toUpper(name[name.len - 1])});
    } else {
        try writer.print("{c}{s}", .{ std.ascii.toUpper(name[2]), name[3..] });
    }
}

const alias_types = std.StaticStringMap([]const u8).initComptime(.{
    .{ "GLenum", "u32" },
    .{ "GLboolean", "u8" },
    .{ "GLbitfield", "u32" },
    .{ "GLclampx", "i32" },
    .{ "GLsizei", "i32" },
    .{ "GLclampf", "f32" },
    .{ "GLclampd", "f64" },
    .{ "GLeglClientBufferEXT", "?*anyopaque" },
    .{ "GLeglImageOES", "?*anyopaque" },
    .{ "GLhandleARB", "if (builtin.os.tag == .macos) ?*anyopaque else u32" },
    .{ "GLfixed", "i32" },
    .{ "GLsync", "?*opaque {}" },
    .{ "struct _cl_context", "opaque {}" },
    .{ "struct _cl_event", "opaque {}" },
    .{ "GLDEBUGPROC", "?*const fn (source: Enum, type: Enum, id: u32, severity: Enum, length: SizeI, message: [*c]const u8, userparam: ?*const anyopaque) callconv(APIENTRY) void" },
    .{ "GLDEBUGPROCARB", "?*const fn (source: Enum, type: Enum, id: u32, severity: Enum, length: SizeI, message: [*c]const u8, userparam: ?*const anyopaque) callconv(APIENTRY) void" },
    .{ "GLDEBUGPROCKHR", "?*const fn (source: Enum, type: Enum, id: u32, severity: Enum, length: SizeI, message: [*c]const u8, userparam: ?*const anyopaque) callconv(APIENTRY) void" },
    .{ "GLDEBUGPROCAMD", "?*const fn (id: Enum, category: Enum, severity: Enum, length: SizeI, message: [*c]const u8, userParam: ?*anyopaque) callconv(APIENTRY) void" },
    .{ "GLvdpauSurfaceNV", "isize" },
    .{ "GLVULKANPROCNV", "?*const fn () callconv(APIENTRY) void" },
});

const rewrite_types = std.StaticStringMap([]const u8).initComptime(.{
    .{ "GLvoid", "" },
    .{ "GLbyte", "i8" },
    .{ "GLubyte", "u8" },
    .{ "GLshort", "i16" },
    .{ "GLushort", "u16" },
    .{ "GLint", "i32" },
    .{ "GLuint", "u32" },
    .{ "GLfloat", "f32" },
    .{ "GLdouble", "f64" },
    .{ "GLchar", "u8" },
    .{ "GLcharARB", "u8" },
    .{ "GLhalf", "u16" },
    .{ "GLhalfARB", "u16" },
    .{ "GLintptr", "isize" },
    .{ "GLintptrARB", "isize" },
    .{ "GLsizeiptr", "isize" },
    .{ "GLsizeiptrARB", "isize" },
    .{ "GLint64", "i64" },
    .{ "GLint64EXT", "i64" },
    .{ "GLuint64", "u64" },
    .{ "GLuint64EXT", "u64" },
    .{ "GLhalfNV", "u16" },
});

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const buffer = try allocator.alloc(u8, @intCast(try file.getEndPos()));
    var reader = file.reader(buffer);
    try reader.interface.fill(buffer.len);
    return buffer;
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
