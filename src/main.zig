const std = @import("std");
const search = @import("search.zig");
const config = @import("config.zig");
const history = @import("history.zig");
const completion = @import("completion.zig");
const clipboard = @import("clipboard.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Check for help flags
    if (args.len >= 2) {
        const first_arg = args[1];
        if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help")) {
            try printHelp();
            return;
        }
    }

    if (args.len < 2) {
        try std.fs.File.stderr().writeAll("Usage: fend [-l|-lc|-z] <pattern>\n");
        try std.fs.File.stderr().writeAll("       fend -h|--help\n");
        std.process.exit(1);
    }

    var cfg = try config.Config.load(allocator);
    defer cfg.deinit(allocator);

    const flag = args[1];
    const pattern = if (args.len > 2) args[2] else args[1];

    if (std.mem.eql(u8, flag, "-l")) {
        // List all matches
        try listMatches(allocator, pattern, &cfg);
    } else if (std.mem.eql(u8, flag, "-lc")) {
        // Copy first result to clipboard
        try copyFirstToClipboard(allocator, pattern, &cfg);
    } else if (std.mem.eql(u8, flag, "-z")) {
        // Navigate and list
        try navigateAndList(allocator, pattern, &cfg);
    } else {
        // Interactive completion menu
        try interactiveMenu(allocator, pattern, &cfg);
    }
}

fn listMatches(allocator: std.mem.Allocator, pattern: []const u8, cfg: *const config.Config) !void {
    const root = "/";
    const search_opts = search.SearchOptions{
        .exclude_patterns = cfg.search.exclude,
        .max_depth = cfg.search.max_depth,
        .respect_gitignore = cfg.search.respect_gitignore,
    };

    var results = try search.searchFiles(allocator, pattern, root, search_opts);
    defer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit(allocator);
    }

    const stdout = std.fs.File.stdout();
    for (results.items) |path| {
        try stdout.writeAll(path);
        try stdout.writeAll("\n");
    }
}

fn copyFirstToClipboard(allocator: std.mem.Allocator, pattern: []const u8, cfg: *const config.Config) !void {
    const root = "/";
    const search_opts = search.SearchOptions{
        .exclude_patterns = cfg.search.exclude,
        .max_depth = cfg.search.max_depth,
        .respect_gitignore = cfg.search.respect_gitignore,
    };

    var results = try search.searchFiles(allocator, pattern, root, search_opts);
    defer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit(allocator);
    }

    if (results.items.len > 0) {
        try clipboard.copyToClipboard(allocator, results.items[0]);
    }
}

fn navigateAndList(allocator: std.mem.Allocator, pattern: []const u8, cfg: *const config.Config) !void {
    const root = "/";
    const search_opts = search.SearchOptions{
        .exclude_patterns = cfg.search.exclude,
        .max_depth = cfg.search.max_depth,
        .respect_gitignore = cfg.search.respect_gitignore,
    };

    var results = try search.searchFiles(allocator, pattern, root, search_opts);
    defer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit(allocator);
    }

    if (results.items.len == 0) {
        try std.fs.File.stderr().writeAll("No matches found\n");
        return;
    }

    const first_match = results.items[0];
    const dir_path = std.fs.path.dirname(first_match) orelse "/";

    // Record in history
    const history_path = try history.History.getHistoryPath(allocator);
    defer allocator.free(history_path);
    var hist = try history.History.init(allocator, history_path);
    defer hist.deinit();
    try hist.record(first_match);

    // Output cd command
    const stdout = std.fs.File.stdout();
    try stdout.writeAll("cd ");
    try stdout.writeAll(dir_path);
    try stdout.writeAll("\n");

    // Spawn lsd or ls
    var child = std.process.Child.init(&.{ "lsd", dir_path }, allocator);
    _ = child.spawnAndWait() catch {
        // Fallback to ls if lsd not found
        var ls_child = std.process.Child.init(&.{ "ls", "-la", dir_path }, allocator);
        _ = try ls_child.spawnAndWait();
    };
}

fn interactiveMenu(allocator: std.mem.Allocator, pattern: []const u8, cfg: *const config.Config) !void {
    const root = "/";
    const search_opts = search.SearchOptions{
        .exclude_patterns = cfg.search.exclude,
        .max_depth = cfg.search.max_depth,
        .respect_gitignore = cfg.search.respect_gitignore,
    };

    var results = try search.searchFiles(allocator, pattern, root, search_opts);
    defer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit(allocator);
    }

    if (results.items.len == 0) {
        try std.fs.File.stderr().writeAll("No matches found\n");
        return;
    }

    const stdout = std.fs.File.stdout();
    var selected_idx: usize = 0;
    if (try completion.showCompletionMenu(allocator, results.items, &selected_idx)) |selected| {
        defer allocator.free(selected);
        try stdout.writeAll(selected);
        try stdout.writeAll("\n");

        // Record in history
        const history_path = try history.History.getHistoryPath(allocator);
        defer allocator.free(history_path);
        var hist = try history.History.init(allocator, history_path);
        defer hist.deinit();
        try hist.record(selected);
    } else {
        // Cancelled
    }
}

fn printHelp() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\fend - Fast file finder with frecency-based history
        \\
        \\USAGE:
        \\    fend [OPTIONS] <pattern>
        \\
        \\OPTIONS:
        \\    -l          List all matching files
        \\    -lc         Copy first match to clipboard
        \\    -z          Navigate to directory and list files
        \\    -h, --help  Show this help message
        \\
        \\EXAMPLES:
        \\    fend main.zig              # Interactive menu to select a file
        \\    fend -l config             # List all files matching "config"
        \\    fend -lc README            # Copy first README match to clipboard
        \\    fend -z src                # Navigate to src directory and list
        \\
        \\The interactive menu supports:
        \\    Arrow keys    Navigate
        \\    Enter         Select
        \\    Esc           Cancel
        \\    s             Open directory in superfile
        \\    g             Open directory in GUI file manager
        \\
    );
}
