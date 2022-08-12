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
image_path_list: std.ArrayListUnmanaged([:0]const u8) = .{},
image_path_list_scroll: rl.Vector2 = std.mem.zeroes(rl.Vector2),
hovered_path: ?[:0]const u8 = null,
hovered_image: ?rl.Texture = null,

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
    widget.clearImagePathList();
    widget.clearHovered();
    widget.* = undefined;
}

pub fn draw(widget: *SearchColumn, arena: std.mem.Allocator, start_x: f32, start_y: f32, width: f32, height: f32) !void {
    const pad = 16;
    const gap = 8;
    const lh = 28; // line height

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

        if (path) |p| try widget.setBase(p);
    }

    // search box
    y += lh + gap;
    if (rl.GuiTextBox(rl.Rectangle.init(x, y, width, lh + gap), widget.search_buffer, widget.search_edit_mode))
        widget.search_edit_mode = !widget.search_edit_mode;

    // search box placeholder
    y += gap / 2;
    rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_DISABLED));
    if (widget.search_buffer[0] == 0)
        rl.GuiLabel(rl.Rectangle.init(x + gap / 2, y, width, lh), "Search...");
    rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL));
    y += gap / 2;

    y += lh + gap;
    const image_path_list_height = @intToFloat(f32, widget.image_path_list.items.len) * (lh + gap);
    const view = rl.GuiScrollPanel(
        rl.Rectangle.init(x, y, width, height - pad - y),
        null,
        rl.Rectangle.init(x, y, width - pad * 2, image_path_list_height),
        &widget.image_path_list_scroll,
    ).asInt();
    rl.BeginScissorMode(view.x, view.y, view.width, view.height);
    y += pad;
    var is_hovering = false;
    for (widget.image_path_list.items) |path| {
        const list_item_bounds = rl.Rectangle.init(
            x + pad + widget.image_path_list_scroll.x,
            y + widget.image_path_list_scroll.y,
            width,
            lh,
        );
        if (rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item_bounds)) {
            is_hovering = true;
            rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.BUTTON, rl.TEXT_COLOR_FOCUSED));

            const replace_hovered_path = if (widget.hovered_path) |hp| !std.mem.eql(u8, hp, path) else true;
            if (replace_hovered_path) {
                if (widget.hovered_path) |hp| widget.allocator.free(hp);
                widget.hovered_path = try widget.allocator.dupeZ(u8, path);
                const hovered_full_path = try std.fmt.allocPrintZ(arena, "{s}/{s}", .{ widget.base.?, widget.hovered_path.? });
                widget.hovered_image = rl.LoadTexture(hovered_full_path);
            }
        }
        rl.GuiLabel(list_item_bounds, path);
        rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL));
        y += lh + gap;
    }
    rl.EndScissorMode();

    if (!is_hovering) widget.clearHovered();
}

fn setBase(widget: *SearchColumn, base: []const u8) !void {
    if (widget.base) |b| widget.allocator.free(b);
    widget.base = try widget.allocator.dupe(u8, base);
    errdefer {
        widget.allocator.free(widget.base.?);
        widget.base = null;
    }

    var d = try std.fs.openIterableDirAbsolute(base, .{});
    defer d.close();

    var di = try d.walk(widget.allocator);
    defer di.deinit();

    widget.clearImagePathList();
    errdefer widget.clearImagePathList();

    while (try di.next()) |entry| {
        if (entry.kind != .File) continue;
        if (entry.path.len < 4 or !std.mem.eql(u8, entry.path[entry.path.len - 4 ..], ".png")) continue;
        try widget.image_path_list.append(
            widget.allocator,
            try widget.allocator.dupeZ(u8, entry.path),
        );
    }
}

fn clearImagePathList(widget: *SearchColumn) void {
    for (widget.image_path_list.items) |path| widget.allocator.free(path);
    widget.image_path_list.deinit(widget.allocator);
    widget.image_path_list = .{};
}

fn clearHovered(widget: *SearchColumn) void {
    if (widget.hovered_path) |hp| widget.allocator.free(hp);
    if (widget.hovered_image) |im| rl.UnloadTexture(im);
    widget.hovered_path = null;
    widget.hovered_image = null;
}
