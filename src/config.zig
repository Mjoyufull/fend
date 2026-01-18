const std = @import("std");

pub const Config = struct {
    file_manager: FileManager = .{},
    search: SearchConfig = .{},

    pub const FileManager = struct {
        superfile: []const u8 = "superfile",
        gui: []const u8 = "thunar",
    };

    pub const SearchConfig = struct {
        exclude: []const []const u8 = &.{ "node_modules", ".git", "target", "build", ".cache" },
        max_depth: ?usize = null,
        respect_gitignore: bool = true,
    };

    pub fn load(allocator: std.mem.Allocator) !Config {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
        const config_path = try std.fmt.allocPrint(allocator, "{s}/.config/fend/config.toml", .{home});
        defer allocator.free(config_path);

        _ = std.fs.openFileAbsolute(config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Return default config
                return Config{};
            }
            return err;
        };

        // TODO: Parse TOML (for now, return defaults)
        // For minimal implementation, we'll use defaults and env vars
        return Config{};
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // TODO: Free allocated strings when TOML parsing is added
    }
};

