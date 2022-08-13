const std = @import("std");

const rl = struct {
    usingnamespace @import("raylib");
    usingnamespace @import("raygui");
};

const SearchColumn = @import("SearchColumn.zig");
const ImagePreview = @import("ImagePreview.zig");
const EditorCanvas = @import("EditorCanvas.zig");

pub fn main() void {
    fallibleMain() catch @panic("Unexpected error");
}

fn fallibleMain() !void {
    const allocator = std.heap.c_allocator;

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1600, 900, "Lair of the Evil Guzzler");
    rl.SetWindowMinSize(800, 600);
    rl.SetTargetFPS(60);

    const pixel_operator_data = @embedFile("../raylib/raygui/styles/dark/PixelOperator.ttf");
    const pixel_operator = rl.LoadFontFromMemory(".ttf", pixel_operator_data, 20, null);
    rl.GuiSetFont(pixel_operator);
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 20);

    var search_column = try SearchColumn.init(allocator);
    defer search_column.deinit();
    var image_preview = ImagePreview.init();
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

        if (search_column.clicked_image) |clicked_image| {
            image_preview.image = clicked_image;
            image_preview.draw(rl.Rectangle.init(0, 0, width * 0.6, height));

            if (rl.GuiButton(rl.Rectangle.init(width - 100 - 16, 16, 100, 40), "Back")) {
                search_column.clicked_path = null;
            }
        } else {
            try search_column.draw(arena.allocator(), 0, 0, width * 0.6, height);
            if (search_column.hovered_image) |*hovered_image| {
                image_preview.image = hovered_image;
                image_preview.draw(rl.Rectangle.init(width * 0.6, 0, width * 0.4, height));
            }
        }
    }
}
