const std = @import("std");
const rl = struct {
    usingnamespace @import("raylib");
    usingnamespace @import("raygui");
};

const ImagePreview = @This();

image: *rl.Texture = undefined,

pub fn init() ImagePreview {
    return ImagePreview{};
}

pub fn draw(widget: *ImagePreview, bounds: rl.Rectangle) void {
    const pad = 16;

    const container_width = bounds.width * 0.4 - pad * 2;
    const container_height = bounds.height - pad * 2;
    const scale_x = container_width / @intToFloat(f32, widget.image.width);
    const scale_y = container_height / @intToFloat(f32, widget.image.height);
    const scale = if (scale_x < scale_y) scale_x else scale_y;

    rl.DrawTextureEx(
        widget.image.*,
        rl.Vector2.init(bounds.x + pad, bounds.y + pad),
        0,
        scale,
        rl.WHITE,
    );
}
