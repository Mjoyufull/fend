# fend

Fast file finder. Searches your entire filesystem and lets you pick files quickly.

Works great with `goto` - they share history so `goto` learns from files you open with `fend`.

## Building

```bash
zig build
```

Binary ends up in `zig-out/bin/fend`.

## Usage

### List all matches

```bash
fend -l zoom.sh
```

Prints all files matching "zoom.sh" to stdout, one per line.

### Copy first match to clipboard

```bash
fend -lc zoom.sh
```

Finds the first match and copies its path to your clipboard. Works with both Wayland and X11. Falls back to `wl-copy` or `xclip` if raw protocol implementation isn't available.

### Interactive selection

```bash
fend zoom.sh
```

Shows a menu below your terminal line with all matches. Navigate with arrow keys:
- Up/Down: Move selection
- Enter: Select and print path
- S: Open parent directory in superfile (or whatever `SUPERFILE_CMD` env var is set to)
- G: Open parent directory in GUI file manager (or whatever `GUI_FILEMANAGER` env var is set to)
- Esc: Cancel

Selected files are automatically recorded in history for `goto` to use.

### Navigate and list

```bash
fend -z zoom.sh
```

Finds the first match, changes to its directory, and runs `lsd` (falls back to `ls -la` if lsd isn't found). Outputs a `cd` command you can eval in your shell. Also records the file in history.

## Configuration

Config file at `~/.config/fend/config.toml`:

```toml
[file_manager]
superfile = "superfile"
gui = "thunar"

[search]
exclude = ["node_modules", ".git", "target", "build", ".cache"]
max_depth = 100
respect_gitignore = true
```

Defaults are used if the config file doesn't exist. Environment variables `SUPERFILE_CMD` and `GUI_FILEMANAGER` override the config.

## How it works

Searches recursively from root by default. Respects exclusion patterns and `.gitignore` files (when implemented). Uses substring matching - case sensitive by default.

History is stored in `~/.local/share/fend/history` in a binary format, shared with `goto` for frecency tracking.

