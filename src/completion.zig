const std = @import("std");

pub fn showCompletionMenu(
    allocator: std.mem.Allocator,
    results: []const []const u8,
    selected_idx: *usize,
) !?[]const u8 {
    const stdin = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout = stdout_file.writer(&stdout_buf);

    // Save cursor position
    try stdout.interface.writeAll("\x1b[s");

    while (true) {
        // Clear menu area and redraw
        try stdout.interface.writeAll("\x1b[u");
        try stdout.interface.writeAll("\x1b[2K"); // Clear line

        // Draw menu
        for (results, 0..) |result, i| {
            if (i == selected_idx.*) {
                try stdout.interface.writeAll("\x1b[7m"); // Reverse video
            }
            try stdout.interface.print("{s}\n", .{result});
            if (i == selected_idx.*) {
                try stdout.interface.writeAll("\x1b[27m"); // Reset
            }
        }

        // Read input (non-blocking would be better, but simple for now)
        var buf: [1]u8 = undefined;
        const n = try stdin.read(&buf);
        if (n == 0) continue;

        const ch = buf[0];

        switch (ch) {
            '\x1b' => {
                // Escape sequence
                var seq_buf: [2]u8 = undefined;
                const seq_n = try stdin.read(&seq_buf);
                if (seq_n == 2 and seq_buf[0] == '[') {
                    switch (seq_buf[1]) {
                        'A' => {
                            // Up arrow
                            if (selected_idx.* > 0) {
                                selected_idx.* -= 1;
                            }
                        },
                        'B' => {
                            // Down arrow
                            if (selected_idx.* < results.len - 1) {
                                selected_idx.* += 1;
                            }
                        },
                        else => {},
                    }
                } else {
                    // Just Esc - cancel
                    try stdout.interface.writeAll("\x1b[u");
                    try stdout.interface.writeAll("\x1b[2K");
                    return null;
                }
            },
            '\r', '\n' => {
                // Enter - select
                try stdout.interface.writeAll("\x1b[u");
                try stdout.interface.writeAll("\x1b[2K");
                const selected = results[selected_idx.*];
                const result_copy = try allocator.dupe(u8, selected);
                return result_copy;
            },
            'S', 's' => {
                // Open in superfile
                const selected = results[selected_idx.*];
                const dir = std.fs.path.dirname(selected) orelse "/";
                try openInSuperfile(allocator, dir);
                continue;
            },
            'G', 'g' => {
                // Open in GUI file manager
                const selected = results[selected_idx.*];
                const dir = std.fs.path.dirname(selected) orelse "/";
                try openInGuiFileManager(allocator, dir);
                continue;
            },
            else => {},
        }
    }
}

fn openInSuperfile(allocator: std.mem.Allocator, dir: []const u8) !void {
    const superfile_cmd = std.posix.getenv("SUPERFILE_CMD") orelse "superfile";
    var child = std.process.Child.init(&.{ superfile_cmd, dir }, allocator);
    _ = child.spawn() catch return;
    _ = child.wait() catch {};
}

fn openInGuiFileManager(allocator: std.mem.Allocator, dir: []const u8) !void {
    const gui_cmd = std.posix.getenv("GUI_FILEMANAGER") orelse "thunar";
    var child = std.process.Child.init(&.{ gui_cmd, dir }, allocator);
    _ = child.spawn() catch return;
    _ = child.wait() catch {};
}

