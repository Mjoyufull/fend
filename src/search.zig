const std = @import("std");

const PathList = std.ArrayListUnmanaged([]const u8);
const IgnorePatterns = std.ArrayListUnmanaged([]const u8);

pub const SearchOptions = struct {
    exclude_patterns: []const []const u8 = &.{},
    max_depth: ?usize = null,
    respect_gitignore: bool = true,
};

pub fn searchFiles(
    allocator: std.mem.Allocator,
    pattern: []const u8,
    root_path: []const u8,
    options: SearchOptions,
) !PathList {
    var results = PathList{};
    errdefer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit(allocator);
    }

    // Global gitignore patterns (owned by this function)
    var gitignore_patterns = IgnorePatterns{};
    defer {
        for (gitignore_patterns.items) |p| {
            allocator.free(p);
        }
        gitignore_patterns.deinit(allocator);
    }

    var root_dir = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch |err| {
        if (err == error.AccessDenied or err == error.PermissionDenied) {
            return results; // Return empty results instead of crashing
        }
        return err;
    };
    defer root_dir.close();

    try walkDirectory(
        allocator,
        &results,
        root_dir,
        root_path,
        pattern,
        options,
        &gitignore_patterns,
        0,
    );

    return results;
}

fn walkDirectory(
    allocator: std.mem.Allocator,
    results: *PathList,
    dir: std.fs.Dir,
    current_path: []const u8,
    pattern: []const u8,
    options: SearchOptions,
    gitignore_patterns: *IgnorePatterns,
    depth: usize,
) !void {
    if (options.max_depth) |max| {
        if (depth > max) return;
    }

    // Parse .gitignore in this directory if enabled
    const patterns_before = gitignore_patterns.items.len;
    if (options.respect_gitignore) {
        parseGitignore(allocator, dir, current_path, gitignore_patterns) catch {};
    }
    defer {
        // Remove patterns added in this directory when leaving
        while (gitignore_patterns.items.len > patterns_before) {
            const p = gitignore_patterns.pop() orelse break;
            allocator.free(p);
        }
    }

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const name = entry.name;

        // Check config exclusions
        var should_exclude = false;
        for (options.exclude_patterns) |exclude| {
            if (std.mem.eql(u8, name, exclude)) {
                should_exclude = true;
                break;
            }
        }
        if (should_exclude) continue;

        // Check gitignore patterns
        if (options.respect_gitignore) {
            if (matchesGitignore(name, gitignore_patterns.items)) {
                continue;
            }
        }

        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ current_path, name });
        defer allocator.free(full_path);

        switch (entry.kind) {
            .file => {
                // Check if filename matches pattern
                if (std.mem.indexOf(u8, name, pattern) != null) {
                    const result_path = try allocator.dupe(u8, full_path);
                    try results.append(allocator, result_path);
                }
            },
            .directory => {
                var subdir = dir.openDir(name, .{ .iterate = true }) catch |err| {
                    // Skip directories we can't access
                    if (err == error.AccessDenied or err == error.PermissionDenied) {
                        continue;
                    }
                    return err;
                };
                defer subdir.close();

                try walkDirectory(
                    allocator,
                    results,
                    subdir,
                    full_path,
                    pattern,
                    options,
                    gitignore_patterns,
                    depth + 1,
                );
            },
            else => {},
        }
    }
}

fn parseGitignore(allocator: std.mem.Allocator, dir: std.fs.Dir, current_path: []const u8, patterns: *IgnorePatterns) !void {
    _ = current_path;
    const file = dir.openFile(".gitignore", .{}) catch return;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    const content = buf[0..bytes_read];

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        // Skip empty lines and comments
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Skip negation patterns for simplicity
        if (trimmed[0] == '!') continue;

        // Store pattern (strip trailing slash for directory patterns)
        var pattern = trimmed;
        if (pattern.len > 0 and pattern[pattern.len - 1] == '/') {
            pattern = pattern[0 .. pattern.len - 1];
        }

        const pattern_copy = try allocator.dupe(u8, pattern);
        try patterns.append(allocator, pattern_copy);
    }
}

fn matchesGitignore(name: []const u8, patterns: []const []const u8) bool {
    for (patterns) |pattern| {
        // Simple matching: exact match or glob pattern
        if (std.mem.eql(u8, name, pattern)) {
            return true;
        }

        // Handle * wildcard (simple glob)
        if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
            const prefix = pattern[0..star_pos];
            const suffix = pattern[star_pos + 1 ..];

            if (name.len >= prefix.len + suffix.len) {
                if (std.mem.startsWith(u8, name, prefix) and
                    std.mem.endsWith(u8, name, suffix))
                {
                    return true;
                }
            }
        }
    }
    return false;
}

