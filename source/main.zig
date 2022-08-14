const std = @import("std");
const nfd = @import("nfd");
const rl = struct {
    usingnamespace @import("raylib");
    usingnamespace @import("raygui");
};

const FinderPreview = @import("ImagePreview.zig");
const EditorCanvas = @import("EditorCanvas.zig");

var allocator = std.heap.c_allocator;

pub fn main() void {
    fallibleMain() catch @panic("Unexpected error");
}

fn fallibleMain() !void {
    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1600, 900, "Lair of the Evil Guzzler");
    rl.SetWindowMinSize(800, 600);
    rl.SetTargetFPS(60);

    if (@import("builtin").os.tag == .windows) {
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 24);
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SPACING, 0);
        const segoe_ui = rl.LoadFontEx("c:/windows/fonts/segoeui.ttf", rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE), null);
        rl.GuiSetFont(segoe_ui);
    } else {
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 22);
        const embedded_font_data = @embedFile("../raylib/raygui/styles/enefete/GenericMobileSystemNuevo.ttf");
        const embedded_font = rl.LoadFontFromMemory(".ttf", embedded_font_data, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE), null);
        rl.GuiSetFont(embedded_font);
    }

    var finder_column = try FinderColumn.init();
    defer finder_column.deinit();
    var finder_preview = FinderPreview.init();
    var editor_canvas = EditorCanvas.init(undefined);
    _ = editor_canvas;

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        const width = @intToFloat(f32, rl.GetRenderWidth());
        const height = @intToFloat(f32, rl.GetRenderHeight());

        rl.ClearBackground(rl.RAYWHITE);

        if (finder_column.clicked_image) |clicked_image| {
            _ = clicked_image;
            // image_preview.image = clicked_image;
            // image_preview.draw(rl.Rectangle.init(0, 0, width * 0.6, height));

            if (rl.GuiButton(rl.Rectangle.init(width - 100 - 16, 16, 100, 40), "Back")) {
                finder_column.clicked_image = null;
            }
        } else {
            try finder_column.draw(arena.allocator(), withPadding(rl.Rectangle.init(0, 0, width * 0.6, height), 16));
            if (finder_column.hovered_image) |*hovered_image| {
                finder_preview.image = hovered_image;
                finder_preview.draw(rl.Rectangle.init(width * 0.6, 0, width * 0.4, height));
            }
        }
    }
}

fn withPadding(bounds: rl.Rectangle, padding: f32) rl.Rectangle {
    return rl.Rectangle.init(
        bounds.x + padding,
        bounds.y + padding,
        @maximum(0, bounds.width - padding * 2),
        @maximum(0, bounds.height - padding * 2),
    );
}

fn measureWidth(string: [:0]const u8) f32 {
    return rl.MeasureTextEx(
        rl.GuiGetFont(),
        string,
        @intToFloat(f32, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE)),
        @intToFloat(f32, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SPACING)),
    ).x;
}

fn buttonSize(string: [:0]const u8) rl.Vector2 {
    const width = measureWidth(string);
    const height = @intToFloat(f32, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE));
    return rl.Vector2.init(width + 16, height + 8);
}

fn textBoxPlaceholder(bounds: rl.Rectangle, string: [*:0]const u8) void {
    var height = @intToFloat(f32, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE));
    height = std.math.clamp(height, 0, bounds.height);
    const top_pad = (bounds.height - height) / 2;
    const left_pad = @intToFloat(f32, rl.GuiGetStyle(rl.TEXTBOX, rl.TEXT_PADDING));

    rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_DISABLED));
    rl.GuiLabel(rl.Rectangle.init(bounds.x + left_pad, bounds.y + top_pad, bounds.width - left_pad, height), string);
    rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL));
}

const FinderColumn = struct {
    base: ?[]const u8 = null,
    search_buffer: [:0]u8,
    search_edit_mode: bool = false,
    image_path_list: std.ArrayListUnmanaged([:0]const u8) = .{},
    image_path_list_scroll: rl.Vector2 = std.mem.zeroes(rl.Vector2),
    hovered_path: ?[:0]const u8 = null,
    hovered_image: ?rl.Texture = null,
    clicked_image: ?*rl.Texture = null,

    fn init() !FinderColumn {
        const search_buffer = try allocator.allocSentinel(u8, 1 << 10, 0);
        for (search_buffer) |*b| b.* = 0;
        return FinderColumn{
            .search_buffer = search_buffer,
        };
    }

    pub fn deinit(widget: *FinderColumn) void {
        if (widget.base) |base| allocator.free(base);
        allocator.free(widget.search_buffer);
        widget.clearImagePathList();
        widget.clearHovered();
        widget.* = undefined;
    }

    fn draw(widget: *FinderColumn, arena: std.mem.Allocator, bounds: rl.Rectangle) !void {
        const gap = 8;
        const text_size = @intToFloat(f32, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE));

        var y = bounds.y;

        {
            const base_label = if (widget.base) |base| try std.fmt.allocPrintZ(arena, "Base: {s}", .{base}) else "Choose a base: ";
            const button_label = "Choose";
            const button_size = buttonSize(button_label);

            defer y += button_size.y + gap;

            rl.GuiLabel(rl.Rectangle.init(bounds.x, y, bounds.width, button_size.y), base_label);
            if (rl.GuiButton(
                rl.Rectangle.init(bounds.x + bounds.width - button_size.x, y, button_size.x, button_size.y),
                button_label,
            )) {
                if (try nfd.openFolderDialog(null)) |path| {
                    defer nfd.freePath(path);
                    try widget.setBase(path);
                }
            }
        }

        {
            const search_box_bounds = rl.Rectangle.init(bounds.x, y, bounds.width, text_size + gap);
            defer y += search_box_bounds.height + gap;

            if (rl.GuiTextBox(search_box_bounds, widget.search_buffer, widget.search_edit_mode))
                widget.search_edit_mode = !widget.search_edit_mode;
            if (widget.search_buffer[0] == 0)
                textBoxPlaceholder(search_box_bounds, "Search...");
        }

        const image_path_list_height = @intToFloat(f32, widget.image_path_list.items.len) * (text_size + gap);
        const view = rl.GuiScrollPanel(
            rl.Rectangle.init(bounds.x, y, bounds.width, bounds.height - y),
            null,
            rl.Rectangle.init(bounds.x, y, bounds.width, image_path_list_height),
            &widget.image_path_list_scroll,
        ).asInt();
        rl.BeginScissorMode(view.x, view.y, view.width, view.height);
        y += gap;
        var is_hovering = false;
        for (widget.image_path_list.items) |path| {
            const list_item_bounds = rl.Rectangle.init(
                bounds.x + widget.image_path_list_scroll.x,
                y + widget.image_path_list_scroll.y,
                bounds.width,
                text_size,
            );
            if (rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item_bounds)) {
                is_hovering = true;
                rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.BUTTON, rl.TEXT_COLOR_FOCUSED));

                const replace_hovered_path = if (widget.hovered_path) |hp| !std.mem.eql(u8, hp, path) else true;
                if (replace_hovered_path) {
                    if (widget.hovered_path) |hp| allocator.free(hp);
                    widget.hovered_path = try allocator.dupeZ(u8, path);
                    const hovered_full_path = try std.fmt.allocPrintZ(arena, "{s}/{s}", .{ widget.base.?, widget.hovered_path.? });
                    widget.hovered_image = rl.LoadTexture(hovered_full_path);
                }

                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    widget.clicked_image = &widget.hovered_image.?;
                }
            }
            rl.GuiLabel(list_item_bounds, path);
            rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL));
            y += text_size + gap;
        }
        rl.EndScissorMode();

        if (!is_hovering) widget.clearHovered();
    }

    fn setBase(widget: *FinderColumn, base: []const u8) !void {
        if (widget.base) |b| allocator.free(b);
        widget.base = try allocator.dupe(u8, base);
        errdefer {
            allocator.free(widget.base.?);
            widget.base = null;
        }

        var d = try std.fs.openIterableDirAbsolute(base, .{});
        defer d.close();

        var di = try d.walk(allocator);
        defer di.deinit();

        widget.clearImagePathList();
        errdefer widget.clearImagePathList();

        while (try di.next()) |entry| {
            if (entry.kind != .File) continue;
            if (entry.path.len < 4 or !std.mem.eql(u8, entry.path[entry.path.len - 4 ..], ".png")) continue;
            try widget.image_path_list.append(
                allocator,
                try allocator.dupeZ(u8, entry.path),
            );
        }
    }

    fn clearImagePathList(widget: *FinderColumn) void {
        for (widget.image_path_list.items) |path| allocator.free(path);
        widget.image_path_list.deinit(allocator);
        widget.image_path_list = .{};
    }

    fn clearHovered(widget: *FinderColumn) void {
        if (widget.hovered_path) |hp| allocator.free(hp);
        if (widget.hovered_image) |im| rl.UnloadTexture(im);
        widget.hovered_path = null;
        widget.hovered_image = null;
    }
};
