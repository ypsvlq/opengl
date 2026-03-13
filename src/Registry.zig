const std = @import("std");
const xml = @import("xml.zig");

document: xml.Document,
enum_map: std.StringHashMapUnmanaged([]const u8),
command_map: std.StringHashMapUnmanaged(*xml.Element),
extension_map: std.StringHashMapUnmanaged(*xml.Element),

pub fn init(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
    const document = try xml.parse(std.heap.page_allocator, bytes);

    var enum_map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var enums_iter = document.root.findChildrenByTag("enums");
    while (enums_iter.next()) |enums| {
        var enum_iter = enums.findChildrenByTag("enum");
        while (enum_iter.next()) |value| {
            try enum_map.put(allocator, value.getAttribute("name").?, value.getAttribute("value").?);
        }
    }

    var command_map: std.StringHashMapUnmanaged(*xml.Element) = .empty;
    var commands_iter = document.root.findChildrenByTag("commands");
    while (commands_iter.next()) |commands| {
        var command_iter = commands.findChildrenByTag("command");
        while (command_iter.next()) |command| {
            try command_map.put(allocator, command.findChildByTag("proto").?.getCharData("name").?, command);
        }
    }

    var extension_map: std.StringHashMapUnmanaged(*xml.Element) = .empty;
    var extensions_iter = document.root.findChildrenByTag("extensions");
    while (extensions_iter.next()) |extensions| {
        var extension_iter = extensions.findChildrenByTag("extension");
        while (extension_iter.next()) |extension| {
            try extension_map.put(allocator, extension.getAttribute("name").?, extension);
        }
    }

    return .{
        .document = document,
        .enum_map = enum_map,
        .command_map = command_map,
        .extension_map = extension_map,
    };
}
