const std = @import("std");
const builtin = @import("builtin");
const nfd = @import("nfd");
const rl = struct {
    usingnamespace @import("raylib");
    usingnamespace @import("raygui");
};

var allocator = std.heap.c_allocator;

pub fn main() void {
    fallibleMain() catch @panic("Unexpected error");
}

fn fallibleMain() !void {
    var gpa: if (builtin.mode == .Debug) std.heap.GeneralPurposeAllocator(.{}) else void = .{};
    defer _ = if (builtin.mode == .Debug) gpa.deinit();
    if (builtin.mode == .Debug) allocator = gpa.allocator();

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1600, 900, "Lair of the Evil Guzzler");
    rl.SetWindowMinSize(800, 600);
    rl.SetTargetFPS(60);

    if (builtin.os.tag == .windows) {
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

    var previewing: TextureAndSource = .{};
    var editing: TextureAndSource = .{};

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        const width = @intToFloat(f32, rl.GetRenderWidth());
        const height = @intToFloat(f32, rl.GetRenderHeight());

        rl.ClearBackground(rl.RAYWHITE);

        if (editing.path) |_| {
            // image_preview.image = clicked_image;
            // image_preview.draw(rl.Rectangle.init(0, 0, width * 0.6, height));

            const back_button_size = buttonSize("🔙");
            if (rl.GuiButton(rl.Rectangle.init(width - back_button_size.x - 16, 16, back_button_size.x, back_button_size.y), "🔙")) {
                editing.unload();
            }
        } else {
            try finder_column.draw(arena.allocator(), withPadding(rl.Rectangle.init(0, 0, width * 0.6, height), 16));
            if (finder_column.hovered_path) |hovered_path| {
                const hovered_full_path = try std.fmt.allocPrintZ(arena.allocator(), "{s}/{s}", .{ finder_column.base.?, hovered_path });
                try previewing.setPath(hovered_full_path);

                finderPreview(withPadding(rl.Rectangle.init(width * 0.6, 0, width * 0.4, height), 16), previewing.tx2d);
            } else previewing.unload();

            if (finder_column.clicked_path) |clicked_path| {
                const clicked_full_path = try std.fmt.allocPrintZ(arena.allocator(), "{s}/{s}", .{ finder_column.base.?, clicked_path });
                try editing.setPath(clicked_full_path);
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

const FinderColumn = struct {
    base: ?[]const u8 = null,
    search_buffer: [:0]u8,
    search_edit_mode: bool = false,
    image_path_list: std.ArrayListUnmanaged([:0]const u8) = .{},
    image_path_list_scroll: rl.Vector2 = std.mem.zeroes(rl.Vector2),
    hovered_path: ?[:0]const u8 = null,
    clicked_path: ?[:0]const u8 = null,

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
            var search_box_bounds = rl.Rectangle.init(bounds.x, y, bounds.width, text_size + gap);
            defer y += search_box_bounds.height + gap;

            if (rl.GuiTextBox(search_box_bounds, widget.search_buffer, widget.search_edit_mode))
                widget.search_edit_mode = !widget.search_edit_mode;
            search_box_bounds.x += @intToFloat(f32, rl.GuiGetStyle(rl.TEXTBOX, rl.TEXT_PADDING));
            if (widget.search_buffer[0] == 0) {
                rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_DISABLED));
                rl.GuiLabel(search_box_bounds, "Search...");
                rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL));
            }
        }

        const search_buffer_span = std.mem.sliceTo(widget.search_buffer, 0);
        const search_lower_buffer = try arena.alloc(u8, search_buffer_span.len);
        const search_lower = std.ascii.lowerString(search_lower_buffer, search_buffer_span);

        const scrollbar_width = @intToFloat(f32, rl.GuiGetStyle(rl.DEFAULT, rl.SCROLLBAR_WIDTH));
        const image_path_list_height = @intToFloat(f32, widget.image_path_list.items.len) * (text_size + gap);

        const view = rl.GuiScrollPanel(
            rl.Rectangle.init(bounds.x, y, bounds.width, bounds.height - y),
            null,
            rl.Rectangle.init(bounds.x, y, bounds.width - scrollbar_width, image_path_list_height),
            &widget.image_path_list_scroll,
        ).asInt();
        rl.BeginScissorMode(view.x, view.y, view.width, view.height);

        widget.hovered_path = null;
        widget.clicked_path = null;
        var list_item_position = rl.Vector2.init(
            bounds.x + widget.image_path_list_scroll.x + gap,
            y + widget.image_path_list_scroll.y,
        );
        for (widget.image_path_list.items) |path| {
            if (search_lower.len > 0) {
                const path_lower_buffer = try arena.alloc(u8, path.len);
                const path_lower = std.ascii.lowerString(path_lower_buffer, path);
                if (std.mem.indexOf(u8, path_lower, search_lower) == null) continue;
            }

            const size = buttonSize(path);
            defer list_item_position.y += size.y;

            const list_item_bounds = rl.Rectangle.init(
                list_item_position.x,
                list_item_position.y,
                size.x,
                size.y,
            );
            if (rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item_bounds)) {
                rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.BUTTON, rl.TEXT_COLOR_FOCUSED));

                widget.hovered_path = path;
                if (rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
                    widget.clicked_path = path;
                }
            }
            rl.GuiLabel(list_item_bounds, path);
            rl.GuiSetStyle(rl.LABEL, rl.TEXT_COLOR_NORMAL, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_NORMAL));
        }
        rl.EndScissorMode();
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
        widget.hovered_path = null;
        widget.clicked_path = null;
        for (widget.image_path_list.items) |path| allocator.free(path);
        widget.image_path_list.deinit(allocator);
        widget.image_path_list = .{};
    }
};

pub fn finderPreview(bounds: rl.Rectangle, maybe_texture: ?rl.Texture) void {
    const texture = maybe_texture orelse return;
    const scale_x = bounds.width / @intToFloat(f32, texture.width);
    const scale_y = bounds.height / @intToFloat(f32, texture.height);
    const scale = if (scale_x < scale_y) scale_x else scale_y;
    rl.DrawTextureEx(texture, rl.Vector2.init(bounds.x, bounds.y), 0, scale, rl.WHITE);
}

const TextureAndSource = struct {
    path: ?[:0]const u8 = null,
    tx2d: ?rl.Texture2D = null,

    fn unload(tas: *TextureAndSource) void {
        if (tas.path) |path| allocator.free(path);
        if (tas.tx2d) |tex| rl.UnloadTexture(tex);
        tas.path = null;
        tas.tx2d = null;
    }

    fn setPath(tas: *TextureAndSource, path: [:0]const u8) !void {
        if (tas.path) |tas_path| if (std.mem.eql(u8, tas_path, path)) return;

        tas.unload();
        tas.path = try allocator.dupeZ(u8, path);
        tas.tx2d = rl.LoadTexture(path);
    }
};
