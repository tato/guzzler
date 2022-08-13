const std = @import("std");

const rl = @import("raylib");
const gui = @import("gui.zig");

pub fn main() void {
    fallibleMain() catch @panic("Unexpected error");
}

fn fallibleMain() !void {
    const allocator = std.heap.c_allocator;

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1600, 900, "Lair of the Evil Guzzler");
    rl.SetWindowMinSize(800, 600);
    rl.SetTargetFPS(60);

    gui.init(allocator);

    const pixel_operator_data = @embedFile("../raylib/raygui/styles/dark/PixelOperator.ttf");
    const pixel_operator = rl.LoadFontFromMemory(".ttf", pixel_operator_data, 20, null);
    gui.setFont(pixel_operator);

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);

        gui.begin();
        defer gui.end();

        // gui.push(gui.layout(.vertical));

        // gui.push(gui.layout(.horizontal));
        gui.label("Choose a base...");
        // gui.label("Choose");
        // gui.pop();

        gui.label("Search...");

        // gui.pop();
    }
}
