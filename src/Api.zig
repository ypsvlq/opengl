const std = @import("std");
const xml = @import("xml.zig");
const Registry = @import("Registry.zig");

enums: std.StringArrayHashMapUnmanaged(void) = .empty,
commands: std.StringHashMapUnmanaged(void) = .empty,

pub const Target = struct {
    api: []const u8,
    version: []const u8,
    profile: []const u8,
};

pub fn init(allocator: std.mem.Allocator, registry: Registry, target: Target, extensions: []const []const u8) !@This() {
    var self: @This() = .{};

    var feature_iter = registry.document.root.findChildrenByTag("feature");
    var feature: *xml.Element = feature_iter.next().?;
    while (!std.mem.eql(u8, feature.getAttribute("api").?, target.api)) {
        feature = feature_iter.next() orelse return error.InvalidApi;
    }
    try self.add(allocator, feature, target);
    while (!std.mem.eql(u8, feature.getAttribute("number").?, target.version)) {
        feature = feature_iter.next() orelse return error.InvalidTarget;
        try self.add(allocator, feature, target);
    }

    for (extensions) |name| {
        try self.add(allocator, registry.extension_map.get(name) orelse return error.UnknownExtension, target);
    }

    return self;
}

fn add(self: *@This(), allocator: std.mem.Allocator, root: *xml.Element, target: Target) !void {
    var require_iter = root.findChildrenByTag("require");
    while (require_iter.next()) |require| {
        if (require.getAttribute("api")) |api| if (!std.mem.eql(u8, api, target.api)) continue;
        if (require.getAttribute("profile")) |profile| if (!std.mem.eql(u8, profile, target.profile)) continue;
        var iter = require.iterator();
        while (iter.next()) |content| {
            const element = if (content.* == .element) content.element else continue;
            const name = element.getAttribute("name").?;
            if (std.mem.eql(u8, element.tag, "enum")) {
                try self.enums.put(allocator, name, {});
            } else if (std.mem.eql(u8, element.tag, "command")) {
                try self.commands.put(allocator, name, {});
            } else if (std.mem.eql(u8, element.tag, "type")) {
                // ignore
            } else {
                return error.UnknownTag;
            }
        }
    }
    var remove_iter = root.findChildrenByTag("remove");
    while (remove_iter.next()) |remove| {
        if (remove.getAttribute("api")) |api| if (!std.mem.eql(u8, api, target.api)) continue;
        if (remove.getAttribute("profile")) |profile| if (!std.mem.eql(u8, profile, target.profile)) continue;
        var iter = remove.iterator();
        while (iter.next()) |content| {
            const element = if (content.* == .element) content.element else continue;
            const name = element.getAttribute("name").?;
            if (std.mem.eql(u8, element.tag, "enum")) {
                _ = self.enums.swapRemove(name);
            } else if (std.mem.eql(u8, element.tag, "command")) {
                _ = self.commands.remove(name);
            } else if (std.mem.eql(u8, element.tag, "type")) {
                // ignore
            } else {
                return error.UnknownTag;
            }
        }
    }
}
