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
    const pixel_operator = rl.LoadFontFromMemory(".ttf", pixel_operator_data, 28, null);
    gui.setFont(pixel_operator);

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);

        gui.begin();
        defer gui.end();

        {
            const search_column = gui.blockLayout("search column", .y);
            search_column.semantic_size[0] = .{ .kind = .percent_of_parent, .value = 0.6, .strictness = 1 };
            search_column.semantic_size[1] = .{ .kind = .percent_of_parent, .value = 1, .strictness = 1 };
            gui.pushParent(search_column);
            defer gui.popParent();

            {
                const base_chooser = gui.blockLayout("base chooser", .x);
                base_chooser.semantic_size[0] = .{ .kind = .percent_of_parent, .value = 1, .strictness = 1 };
                base_chooser.semantic_size[1] = .{ .kind = .children_sum, .value = 0, .strictness = 1 };
                gui.pushParent(base_chooser);
                defer gui.popParent();

                gui.label("Choose a base...");
                gui.label("Choose");
            }

            gui.label("Search...");
        }
    }
}
