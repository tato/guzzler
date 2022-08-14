const std = @import("std");

const rl = @import("raylib");
const nfd = @import("nfd");
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

    const segoe_ui = rl.LoadFontEx("c:/windows/fonts/segoeui.ttf", 28, null);
    gui.setFont(segoe_ui);

    while (!rl.WindowShouldClose()) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.RAYWHITE);

        gui.begin();
        defer gui.end();

        {
            gui.pushParent(gui.blockLayout("search column", .y));
            gui.withSize(
                gui.Size.init(.percent_of_parent, 0.6, 1),
                gui.Size.init(.percent_of_parent, 1, 1),
            );
            gui.withBorder();
            defer gui.popParent();

            {
                gui.pushParent(gui.blockLayout("base chooser", .x));
                gui.withSize(
                    gui.Size.init(.percent_of_parent, 1, 1),
                    gui.Size.init(.children_sum, 1, 1),
                );
                defer gui.popParent();

                gui.label("Choose a base...");
                gui.withSize(gui.Size.init(.percent_of_parent, 1, 0), gui.Size.init(.text_content, 1, 1));

                if (gui.button("Choose")) {
                    const path = nfd.openFolderDialog(null) catch @panic("nativefiledialog returned with error");
                    defer if (path) |p| nfd.freePath(p);

                    std.log.info("PATH: {?s}", .{path});
                }
                gui.withBorder();
            }

            gui.label("Search...");
            gui.withSize(gui.Size.init(.percent_of_parent, 1, 1), gui.Size.init(.text_content, 1, 1));
        }
    }
}
