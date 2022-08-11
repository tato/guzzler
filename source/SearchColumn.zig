const std = @import("std");
const rl = struct {
    usingnamespace @import("raylib");
    usingnamespace @import("raygui");
};
const nfd = @import("nfd");

const SearchColumn = @This();

allocator: std.mem.Allocator,
base: ?[]const u8 = null,
search_buffer: [:0]u8,
search_edit_mode: bool = false,

pub fn init(allocator: std.mem.Allocator) !SearchColumn {
    var col = SearchColumn{
        .allocator = allocator,
        .search_buffer = try allocator.allocSentinel(u8, 256, 0),
    };
    for (col.search_buffer) |*b| b.* = 0;
    return col;
}

pub fn deinit(widget: *SearchColumn) void {
    if (widget.base) |base| widget.allocator.free(base);
    widget.allocator.free(widget.search_buffer);
    widget.* = undefined;
}

pub fn draw(widget: *SearchColumn, arena: std.mem.Allocator, start_x: f32, start_y: f32, width: f32, height: f32) !void {
    _ = height;

    const pad = 16;
    const gap = 8;
    const lh = 30; // line height

    var x: f32 = start_x + pad;
    var y: f32 = start_y + pad;

    const choose_button_width = 80;
    const base_label_text = if (widget.base) |base| blk: {
        break :blk try std.fmt.allocPrintZ(arena, "Base: {s}", .{base});
    } else "Choose a base: ";
    rl.GuiLabel(rl.Rectangle.init(x, y, width - choose_button_width, lh), base_label_text);
    if (rl.GuiButton(rl.Rectangle.init(x + width - choose_button_width, y, choose_button_width, lh), "Choose")) {
        const path = nfd.openFolderDialog(null) catch @panic("nativefiledialog returned with error");
        defer if (path) |p| nfd.freePath(p);

        if (path) |p| widget.base = try widget.allocator.dupe(u8, p);
    }

    y += lh + gap;
    if (rl.GuiTextBox(rl.Rectangle.init(x, y, width, lh), widget.search_buffer, widget.search_edit_mode))
        widget.search_edit_mode = !widget.search_edit_mode;

    const default_color = rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL);
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL, 0x101010ff);
    if (widget.search_buffer[0] == 0)
        rl.GuiLabel(rl.Rectangle.init(x + 4, y, width, lh), "Search...");
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL, default_color);
}
