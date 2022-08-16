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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    if (builtin.mode == .Debug) allocator = gpa.allocator();

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1600, 900, "Lair of the Evil Guzzler");
    rl.SetWindowMinSize(800, 600);
    rl.SetTargetFPS(60);

    rl.GuiLoadStyle(themes[current_theme]);

    setGuiFont();

    var finder_column = try FinderColumn.init();
    defer finder_column.deinit();
    var single_sheet_editor = try SingleSheetEditor.init();
    defer single_sheet_editor.deinit();

    var previewing: TextureAndSource = .{};
    var editing: TextureAndSource = .{};

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        const width = @intToFloat(f32, rl.GetRenderWidth());
        const height = @intToFloat(f32, rl.GetRenderHeight());

        handleThemeSwap();

        rl.ClearBackground(rl.GetColor(@bitCast(c_uint, rl.GuiGetStyle(rl.DEFAULT, rl.BACKGROUND_COLOR))));

        if (editing.path) |_| {
            try single_sheet_editor.draw(arena.allocator(), withPadding(rl.Rectangle.init(0, 0, width, height), 8), &editing);
        } else {
            try finder_column.draw(arena.allocator(), withPadding(rl.Rectangle.init(0, 0, width * 0.6, height), 8));
            if (finder_column.hovered_path) |hovered_path| {
                try previewing.setPath(finder_column.base, hovered_path);

                finderPreview(withPadding(rl.Rectangle.init(width * 0.6, 0, width * 0.4, height), 8), previewing.tx2d);
            } else previewing.unload();

            if (finder_column.clicked_path) |clicked_path| {
                try editing.setPath(finder_column.base, clicked_path);
            }
        }
    }
}

const themes_path = "c:/code/guzzler_habitat/raylib/raygui/styles/";
const themes = blk: {
    var tt: []const [*:0]const u8 = &.{};
    for (&[_][]const u8{
        "ashes", "bluish", "candy", "cherry", "cyber", "dark", "default", "enefete", "jungle", "lavanda", "sunny", "terminal",
    }) |theme_name| {
        tt = tt ++ &[1][*:0]const u8{themes_path ++ theme_name ++ "/" ++ theme_name ++ ".rgs"};
    }
    break :blk tt;
};
var current_theme: usize = 6;

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

fn setGuiFont() void {
    if (builtin.os.tag == .windows) {
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 24);
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SPACING, 0);
        const segoe_ui = rl.LoadFontEx("c:/windows/fonts/segoeui.ttf", rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE), null);
        rl.GuiSetFont(segoe_ui);
    } else {
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 22);
        const embedded_font_data = @embedFile("raylib/raygui/styles/enefete/GenericMobileSystemNuevo.ttf");
        const embedded_font = rl.LoadFontFromMemory(".ttf", embedded_font_data, rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE), null);
        rl.GuiSetFont(embedded_font);
    }
}

fn handleThemeSwap() void {
    if (rl.IsKeyPressed(rl.KEY_RIGHT)) {
        current_theme = (current_theme + 1) % themes.len;
        rl.GuiLoadStyle(themes[current_theme]);
        setGuiFont();
    }
    if (rl.IsKeyPressed(rl.KEY_LEFT)) {
        current_theme = (current_theme - 1) % themes.len;
        rl.GuiLoadStyle(themes[current_theme]);
        setGuiFont();
    }
}

const FinderColumn = struct {
    base: ?[:0]const u8 = null,
    search_buffer: [:0]u8,
    search_edit_mode: bool = false,
    path_list: std.ArrayListUnmanaged([:0]const u8) = .{},
    path_list_scroll: rl.Vector2 = std.mem.zeroes(rl.Vector2),
    hovered_path: ?[:0]const u8 = null,
    clicked_path: ?[:0]const u8 = null,

    fn init() !FinderColumn {
        const search_buffer = try allocator.allocSentinel(u8, 1 << 10, 0);
        for (search_buffer) |*b| b.* = 0;
        errdefer allocator.free(search_buffer);

        return FinderColumn{
            .search_buffer = search_buffer,
        };
    }

    fn deinit(widget: *FinderColumn) void {
        allocator.free(widget.search_buffer);
        widget.clearBase();
        widget.* = undefined;
    }

    fn clearBase(widget: *FinderColumn) void {
        if (widget.base) |base| allocator.free(base);
        widget.base = null;
        widget.hovered_path = null;
        widget.clicked_path = null;
        for (widget.path_list.items) |path| allocator.free(path);
        widget.path_list.deinit(allocator);
        widget.path_list = .{};
    }

    fn draw(widget: *FinderColumn, arena: std.mem.Allocator, bounds: rl.Rectangle) !void {
        const gap = 4;
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

        const edit_button_label = "Edit";
        const edit_button_size = buttonSize(edit_button_label);
        const filtered_paths = try widget.getFilteredPaths(arena);
        const scrollbar_width = 16; // lol
        const image_path_list_height = @round(@intToFloat(f32, filtered_paths.len) * (edit_button_size.y + gap) + gap);
        const scroll_panel_bounds = rl.Rectangle.init(bounds.x, y, bounds.width, bounds.height - y);
        const scroll_content_bounds = rl.Rectangle.init(bounds.x, y, bounds.width - scrollbar_width, image_path_list_height);

        const view = rl.GuiScrollPanel(
            scroll_panel_bounds,
            null,
            scroll_content_bounds,
            &widget.path_list_scroll,
        ).asInt();
        rl.BeginScissorMode(view.x, view.y, view.width, view.height);

        widget.hovered_path = null;
        widget.clicked_path = null;
        var list_item_position = rl.Vector2.init(
            bounds.x + widget.path_list_scroll.x + gap,
            y + widget.path_list_scroll.y,
        );
        for (filtered_paths) |path| {
            list_item_position.y += gap;
            defer list_item_position.y += edit_button_size.y;

            const list_item_bounds = rl.Rectangle.init(list_item_position.x, list_item_position.y, scroll_content_bounds.width, edit_button_size.y);
            var edit_button_bounds = rl.Rectangle.init(list_item_position.x, list_item_position.y, edit_button_size.x, edit_button_size.y);
            edit_button_bounds.x = scroll_content_bounds.x + scroll_content_bounds.width - edit_button_size.x;

            if (rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item_bounds)) {
                const focused_color = rl.GetColor(@bitCast(c_uint, rl.GuiGetStyle(rl.DEFAULT, rl.BASE_COLOR_FOCUSED)));
                rl.DrawRectangleRec(withPadding(list_item_bounds, -gap / 2), focused_color);
                widget.hovered_path = path;
            }
            rl.GuiLabel(list_item_bounds, path);

            if (rl.GuiButton(edit_button_bounds, edit_button_label)) {
                widget.clicked_path = path;
            }
        }
        rl.EndScissorMode();
    }

    fn setBase(widget: *FinderColumn, base_path: []const u8) !void {
        widget.clearBase();
        errdefer widget.clearBase();

        widget.base = try allocator.dupeZ(u8, base_path);
        errdefer {
            allocator.free(widget.base.?);
            widget.base = null;
        }

        var d = try std.fs.openIterableDirAbsolute(base_path, .{});
        defer d.close();

        var di = try d.walk(allocator);
        defer di.deinit();

        while (try di.next()) |entry| {
            if (entry.kind != .File) continue;
            if (entry.path.len < 4 or !std.mem.eql(u8, entry.path[entry.path.len - 4 ..], ".png")) continue;
            try widget.path_list.append(
                allocator,
                try allocator.dupeZ(u8, entry.path),
            );
        }
    }

    fn getFilteredPaths(widget: FinderColumn, arena: std.mem.Allocator) ![][:0]const u8 {
        const search_buffer_span = std.mem.sliceTo(widget.search_buffer, 0);
        const search_lower_buffer = try arena.alloc(u8, search_buffer_span.len);
        const search_lower = std.ascii.lowerString(search_lower_buffer, search_buffer_span);

        var filtered_list = std.ArrayList([:0]const u8).init(arena);
        for (widget.path_list.items) |path| {
            if (search_lower.len > 0) {
                const path_lower_buffer = try arena.alloc(u8, path.len);
                const path_lower = std.ascii.lowerString(path_lower_buffer, path);
                if (std.mem.indexOf(u8, path_lower, search_lower) == null) continue;
            }
            try filtered_list.append(path);
        }

        return filtered_list.toOwnedSlice();
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

    fn setPath(tas: *TextureAndSource, maybe_base: ?[:0]const u8, path: [:0]const u8) !void {
        const base = maybe_base orelse return error.base_not_present;

        if (tas.path) |stored_path| {
            const len_matches = stored_path.len == base.len + path.len + 1;
            const start_matches = len_matches and std.mem.eql(u8, stored_path[0..base.len], base);
            const end_matches = start_matches and std.mem.eql(u8, stored_path[base.len + 1 ..], path);
            if (end_matches) return;
        }

        const full_path = try std.fmt.allocPrintZ(allocator, "{s}/{s}", .{ base, path });
        tas.unload();
        tas.path = full_path;
        tas.tx2d = rl.LoadTexture(full_path);
    }
};
const SingleSheetEditor = struct {
    w_buffer: [:0]u8,
    w_editing: bool = false,
    w_parsed: ?u15 = null,
    h_buffer: [:0]u8,
    h_editing: bool = false,
    h_parsed: ?u15 = null,

    fn init() !SingleSheetEditor {
        const w_buffer = try allocator.allocSentinel(u8, 1 << 10, 0);
        for (w_buffer) |*b| b.* = 0;
        errdefer allocator.free(w_buffer);

        const h_buffer = try allocator.allocSentinel(u8, 1 << 10, 0);
        for (h_buffer) |*b| b.* = 0;
        errdefer allocator.free(h_buffer);

        return SingleSheetEditor{ .w_buffer = w_buffer, .h_buffer = h_buffer };
    }

    fn deinit(widget: *SingleSheetEditor) void {
        allocator.free(widget.w_buffer);
        allocator.free(widget.h_buffer);
    }

    fn draw(widget: *SingleSheetEditor, arena: std.mem.Allocator, bounds: rl.Rectangle, editing: *TextureAndSource) !void {
        _ = arena;

        const gap = 4;
        const separator_width = 8;
        const canvas_bounds = rl.Rectangle.init(bounds.x, bounds.y, bounds.width * 0.6 - separator_width / 2, bounds.height);
        const controls_start = bounds.x + canvas_bounds.width + separator_width;
        const controls_width = bounds.width - controls_start;
        const controls_bounds = rl.Rectangle.init(controls_start, bounds.y, controls_width, bounds.height);

        drawCanvas(canvas_bounds, editing.tx2d, widget.w_parsed, widget.h_parsed);

        var y = controls_bounds.y;

        {
            const back_button_size = buttonSize("🔙");
            defer y += back_button_size.y + gap;
            if (rl.GuiButton(rl.Rectangle.init(controls_start + controls_width - back_button_size.x, y, back_button_size.x, back_button_size.y), "🔙")) {
                editing.unload();
                return;
            }
        }

        {
            const w_label = "Sprite width";
            const h_label = "Sprite height";
            const box_width = (controls_width - gap) / 2;
            const box_height = buttonSize(w_label).y;
            var w_bounds = rl.Rectangle.init(controls_start, y, box_width, box_height);
            var h_bounds = rl.Rectangle.init(controls_start + box_width + gap, y, box_width, box_height);
            defer y += (box_height + gap) * 2;

            rl.GuiLabel(w_bounds, w_label);
            rl.GuiLabel(h_bounds, h_label);

            w_bounds.y += box_height + gap;
            h_bounds.y += box_height + gap;

            if (rl.GuiTextBox(w_bounds, widget.w_buffer, widget.w_editing)) widget.w_editing = !widget.w_editing;
            if (rl.GuiTextBox(h_bounds, widget.h_buffer, widget.h_editing)) widget.h_editing = !widget.h_editing;

            widget.w_parsed = std.fmt.parseInt(u15, std.mem.sliceTo(widget.w_buffer, 0), 10) catch null;
            widget.h_parsed = std.fmt.parseInt(u15, std.mem.sliceTo(widget.h_buffer, 0), 10) catch null;
        }
    }
};

fn drawCanvas(
    bounds: rl.Rectangle,
    maybe_image: ?rl.Texture2D,
    maybe_sprite_width: ?u15,
    maybe_sprite_height: ?u15,
) void {
    const image = maybe_image orelse return;
    const image_width = @intToFloat(f32, image.width);
    const image_height = @intToFloat(f32, image.height);
    const scale_x = bounds.width / image_width;
    const scale_y = bounds.height / image_height;
    const scale = if (scale_x < scale_y) scale_x else scale_y;
    rl.DrawTextureEx(image, rl.Vector2.init(bounds.x, bounds.y), 0, scale, rl.WHITE);

    const sprite_width = @intToFloat(f32, maybe_sprite_width orelse return);
    const sprite_height = @intToFloat(f32, maybe_sprite_height orelse return);

    const scaled_sprite_width = scale * sprite_width;
    const scaled_sprite_height = scale * sprite_height;

    const line_color = rl.GetColor(@bitCast(c_uint, rl.GuiGetStyle(rl.DEFAULT, rl.BORDER_COLOR_FOCUSED)));
    var hover_color = rl.GetColor(@bitCast(c_uint, rl.GuiGetStyle(rl.DEFAULT, rl.BASE_COLOR_FOCUSED)));
    hover_color.a = @floatToInt(u8, 256.0 * 0.3);

    var x: f32 = 0;
    while (x < image_width * scale) : (x += scaled_sprite_width) {
        rl.DrawLineEx(rl.Vector2.init(bounds.x + x, bounds.y), rl.Vector2.init(bounds.x + x, bounds.y + image_height * scale), 1, line_color);
    }

    var y: f32 = 0;
    while (y < image_height * scale) : (y += scaled_sprite_height) {
        rl.DrawLineEx(rl.Vector2.init(bounds.x, bounds.y + y), rl.Vector2.init(bounds.x + image_width * scale, bounds.y + y), 1, line_color);
    }

    y = 0;
    find_hover: while (y < image_height * scale) : (y += scaled_sprite_height) {
        x = 0;
        while (x < image_width * scale) : (x += scaled_sprite_width) {
            const rect = rl.Rectangle.init(bounds.x + x, bounds.y + y, scaled_sprite_width, scaled_sprite_height);
            if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)) {
                rl.DrawRectangleRec(rect, hover_color);
                break :find_hover;
            }
        }
    }

    // for (const [x, y, name] of spriteNames) {
    //     const spriteRect = [x * scaledSpriteWidth, y * scaledSpriteHeight, scaledSpriteWidth, scaledSpriteHeight]
    //     ctx.fillStyle = "rgba(100, 100, 200, 0.25)"
    //     ctx.fillRect(...spriteRect)

    //     ctx.save()
    //     ctx.beginPath()
    //     ctx.rect(...spriteRect)
    //     ctx.clip()

    //     const textPositioning = [x * scaledSpriteWidth + scaledSpriteWidth * 0.05, y * scaledSpriteHeight + scaledSpriteHeight * 0.9]
    //     ctx.font = "bold 14px sans-serif"
    //     ctx.textAlign = "start"
    //     ctx.strokeStyle = "white"
    //     ctx.strokeText(name, ...textPositioning)
    //     ctx.fillStyle = "black"
    //     ctx.fillText(name, ...textPositioning)

    //     ctx.restore()
    // }
}
