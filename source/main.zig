const std = @import("std");

const rl = struct {
    usingnamespace @import("raylib");
    usingnamespace @import("raygui");
};

const SearchColumn = @import("SearchColumn.zig");

pub fn main() void {
    fallibleMain() catch @panic("Unexpected error");
}

fn fallibleMain() !void {
    const allocator = std.heap.c_allocator;

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(1600, 900, "Lair of the Evil Guzzler");
    rl.SetWindowMinSize(800, 600);
    rl.SetTargetFPS(60);

    var search_column = try SearchColumn.init(allocator);
    defer search_column.deinit();

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        const width = @intToFloat(f32, rl.GetRenderWidth());
        const height = @intToFloat(f32, rl.GetRenderHeight());

        rl.ClearBackground(rl.RAYWHITE);
        try search_column.draw(arena.allocator(), 0, 0, width * 0.6, height);
    }
}
