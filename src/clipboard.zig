const std = @import("std");

pub fn copyToClipboard(allocator: std.mem.Allocator, text: []const u8) !void {
    // Detect display server
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY");
    const x11_display = std.posix.getenv("DISPLAY");

    if (wayland_display != null) {
        try copyToWayland(allocator, text);
    } else if (x11_display != null) {
        try copyToX11(allocator, text);
    } else {
        return error.NoDisplayServer;
    }
}

fn copyToWayland(allocator: std.mem.Allocator, text: []const u8) !void {
    // For now, use wl-clipboard as fallback
    // TODO: Implement raw Wayland protocol
    var child = std.process.Child.init(&.{ "wl-copy" }, allocator);
    child.stdin_behavior = .Pipe;
    _ = try child.spawn();
    if (child.stdin) |stdin| {
        try stdin.writeAll(text);
        stdin.close();
    }
    _ = try child.wait();
}

fn copyToX11(allocator: std.mem.Allocator, text: []const u8) !void {
    // For now, use xclip as fallback
    // TODO: Implement raw X11 protocol
    var child = std.process.Child.init(&.{ "xclip", "-selection", "clipboard" }, allocator);
    child.stdin_behavior = .Pipe;
    _ = try child.spawn();
    if (child.stdin) |stdin| {
        try stdin.writeAll(text);
        stdin.close();
    }
    _ = try child.wait();
}

