const std = @import("std");
const rl = @import("raylib");

var gui: Gui = undefined;
const Gui = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    frame_index: u64 = 0,
    blocks: BlockMap = .{},

    primordial_parent: *Block,
    current_parent: ?*Block = null,
    previous_sibling: ?*Block = null,

    font: rl.Font,
};

const BlockMap = std.AutoHashMapUnmanaged(Key, *Block);

const Block = struct {
    // tree links
    first: ?*Block,
    last: ?*Block,
    next: ?*Block,
    prev: ?*Block,
    parent: ?*Block,

    // key+generation info
    key: Key,
    last_frame_touched_index: u64,

    // per-frame info provided by builders
    flags: BlockFlags,
    string: ?[:0]const u8,
    semantic_size: [Axis.len]Size,

    // computed every frame
    computed_rel_position: [Axis.len]f32,
    computed_size: [Axis.len]f32,
    rect: rl.Rectangle,

    // persistent data
    hot_t: f32,
    active_t: f32,
};

const BlockFlags = packed struct {
    _padding: u32 = 0,

    comptime {
        std.debug.assert(@bitSizeOf(BlockFlags) == 32);
    }
};

const SizeKind = enum {
    none,
    pixels,
    text_content,
    percent_of_parent,
    children_sum,
};

const Size = struct {
    kind: SizeKind,
    value: f32,
    strictness: f32,
};

const Axis = enum {
    x,
    y,
    const len = @typeInfo(Axis).Enum.fields.len;
};

const Key = u64;

pub fn init(gpa: std.mem.Allocator) void {
    const primordial_parent = gpa.create(Block) catch unreachable;
    primordial_parent.* = std.mem.zeroes(Block);
    gui = Gui{
        .gpa = gpa,
        .arena = undefined,
        .primordial_parent = primordial_parent,
        .font = rl.GetFontDefault(),
    };
}

pub fn setFont(font: rl.Font) void {
    gui.font = font;
}

pub fn begin() void {
    gui.arena = std.heap.ArenaAllocator.init(gui.gpa);
    gui.frame_index += 1;
    gui.current_parent = gui.primordial_parent;
    gui.previous_sibling = null;
}

pub fn end() void {
    const lh = @intToFloat(f32, gui.font.baseSize);
    var y: f32 = 0;

    var stack = std.ArrayList(*Block).init(gui.arena.allocator());
    defer stack.deinit();

    stack.append(gui.primordial_parent) catch unreachable;
    while (stack.items.len > 0) {
        const block = stack.pop();

        if (block.string) |string| {
            rl.DrawTextEx(gui.font, string, rl.Vector2.init(0, y), lh, 0, rl.BLACK);
            y += lh;
        }

        if (block.next) |next| stack.append(next) catch unreachable;
        if (block.first) |first| stack.append(first) catch unreachable;
    }

    pruneWidgets() catch unreachable;

    gui.arena.deinit();
}

// pub fn push(block: BlockHandle) void {
//     block.get().?.parent = gui.stack_top;
//     gui.stack_top = block;
// }

// pub fn pop() void {
//     gui.stack_top = gui.stack_top.get().?.parent;
// }

pub fn label(comptime string: [:0]const u8) void {
    const key = keyFromString(string);

    const entry = gui.blocks.getOrPut(gui.gpa, key) catch unreachable;
    if (!entry.found_existing) {
        const block = gui.gpa.create(Block) catch unreachable;
        block.* = std.mem.zeroInit(Block, .{
            .key = key,
        });
        entry.value_ptr.* = block;
    }

    const block = entry.value_ptr.*;
    block.first = null;
    block.last = null;
    block.prev = gui.previous_sibling;
    block.next = null;
    block.parent = gui.current_parent;

    if (gui.previous_sibling) |previous_sibling| previous_sibling.next = block;
    gui.previous_sibling = block;

    if (gui.current_parent) |current_parent| {
        if (current_parent.first == null) current_parent.first = block;
        current_parent.last = block;
    }

    block.flags = .{};
    block.string = string;
    block.semantic_size = undefined;

    block.last_frame_touched_index = gui.frame_index;
}

fn pruneWidgets() !void {
    var remove_blocks = std.ArrayList(Key).init(gui.arena.allocator());
    defer remove_blocks.deinit();

    var blocks_iterator = gui.blocks.iterator();
    while (blocks_iterator.next()) |entry| {
        if (entry.value_ptr.*.last_frame_touched_index < gui.frame_index) {
            gui.gpa.destroy(entry.value_ptr.*);
            try remove_blocks.append(entry.key_ptr.*);
        }
    }

    for (remove_blocks.items) |key| _ = gui.blocks.remove(key);
}

fn keyFromString(string: []const u8) Key {
    return @ptrToInt(string.ptr);
}
