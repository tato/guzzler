const std = @import("std");
const rl = @import("raylib");

var gui: Gui = undefined;
const Gui = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    frame_index: u64 = 0,
    blocks: BlockMap = .{},

    primordial_parent: *Block,
    current_parent: *Block,

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
    layout_axis: Axis = .x,

    // computed every frame
    computed_rel_position: [Axis.len]f32,
    computed_size: [Axis.len]f32,
    rect: rl.Rectangle,

    // persistent data
    hot_t: f32 = 0,
    active_t: f32 = 0,

    pub fn clearPerFrameInfo(block: *Block) void {
        block.flags = .{};
        block.string = null;
        block.semantic_size[0] = .{ .kind = .none, .value = 0, .strictness = 0 };
        block.semantic_size[1] = .{ .kind = .none, .value = 0, .strictness = 0 };
        block.layout_axis = .x;

        block.first = null;
        block.last = null;
        block.next = null;
        block.prev = null;
        block.parent = null;
    }
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
    primordial_parent.semantic_size[0] = .{ .kind = .percent_of_parent, .value = 1, .strictness = 1 };
    primordial_parent.semantic_size[1] = .{ .kind = .percent_of_parent, .value = 1, .strictness = 1 };
    gui = Gui{
        .gpa = gpa,
        .arena = undefined,
        .primordial_parent = primordial_parent,
        .current_parent = primordial_parent,
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
    gui.primordial_parent.clearPerFrameInfo();
}

pub fn end() void {
    calculateStandaloneSizes(gui.primordial_parent);
    calculateUpwardsDependentSizes(gui.primordial_parent);
    _ = calculateDownwardsDependentSizes(gui.primordial_parent);
    solveViolations(gui.primordial_parent);
    computeRelativePositions(gui.primordial_parent, .{ 0, 0 });

    const doIt = struct {
        fn doIt(block: *Block) void {
            if (block.string) |string| {
                const position = rl.Vector2.init(block.rect.x, block.rect.y);
                rl.DrawTextEx(gui.font, string, position, @intToFloat(f32, gui.font.baseSize), 0, rl.BLACK);
            }

            if (block.first) |first| doIt(first);
            if (block.next) |next| doIt(next);
        }
    }.doIt;
    doIt(gui.primordial_parent);

    pruneWidgets() catch unreachable;

    gui.arena.deinit();
}

pub fn pushParent(block: *Block) void {
    gui.current_parent = block;
}

pub fn popParent() void {
    gui.current_parent = gui.current_parent.parent.?;
}

pub fn label(comptime string: [:0]const u8) void {
    const block = getOrInsertBlock(string);

    block.string = string;
    block.semantic_size[@enumToInt(Axis.x)].kind = .text_content;
    block.semantic_size[@enumToInt(Axis.y)].kind = .text_content;
}

pub fn blockLayout(comptime string: [:0]const u8, axis: Axis) *Block {
    const block = getOrInsertBlock(string);

    block.semantic_size[@enumToInt(Axis.x)].kind = .children_sum;
    block.semantic_size[@enumToInt(Axis.y)].kind = .children_sum;
    block.layout_axis = axis;

    return block;
}

fn getOrInsertBlock(comptime string: [:0]const u8) *Block {
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
    block.clearPerFrameInfo();

    block.prev = gui.current_parent.last;
    block.parent = gui.current_parent;

    if (block.prev) |previous_sibling| previous_sibling.next = block;

    if (gui.current_parent.first == null) gui.current_parent.first = block;
    gui.current_parent.last = block;

    block.last_frame_touched_index = gui.frame_index;

    return block;
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
    return std.hash.Wyhash.hash(420, string);
}

fn calculateStandaloneSizes(block: *Block) void {
    for (block.semantic_size) |semantic_size, i| {
        switch (semantic_size.kind) {
            .pixels => block.computed_size[i] = semantic_size.value,
            .text_content => {
                block.computed_size[i] = if (block.string) |string| switch (@intToEnum(Axis, i)) {
                    .x => @intToFloat(f32, rl.MeasureText(string, gui.font.baseSize)),
                    .y => @intToFloat(f32, gui.font.baseSize),
                } else 0;
            },
            else => {},
        }
    }

    if (block.first) |first| calculateStandaloneSizes(first);
    if (block.next) |next| calculateStandaloneSizes(next);
}

fn calculateUpwardsDependentSizes(block: *Block) void {
    for (block.semantic_size) |semantic_size, i| {
        switch (semantic_size.kind) {
            .percent_of_parent => {
                if (block.parent) |parent| {
                    switch (parent.semantic_size[i].kind) {
                        .pixels, .text_content, .percent_of_parent => {
                            block.computed_size[i] = parent.computed_size[i] * semantic_size.value;
                        },
                        else => block.computed_size[i] = 0,
                    }
                } else {
                    block.computed_size[i] = switch (@intToEnum(Axis, i)) {
                        .x => @intToFloat(f32, rl.GetScreenWidth()) * semantic_size.value,
                        .y => @intToFloat(f32, rl.GetScreenHeight()) * semantic_size.value,
                    };
                }
            },
            else => {},
        }
    }

    if (block.first) |first| calculateUpwardsDependentSizes(first);
    if (block.next) |next| calculateUpwardsDependentSizes(next);
}

fn calculateDownwardsDependentSizes(block: *Block) [Axis.len]f32 {
    var children_size = [2]f32{ 0, 0 };
    if (block.first) |first| children_size = calculateDownwardsDependentSizes(first);

    for (block.semantic_size) |semantic_size, i| {
        switch (semantic_size.kind) {
            .children_sum => block.computed_size[i] = children_size[i],
            else => {},
        }
    }

    var siblings_size = [2]f32{ 0, 0 };
    if (block.next) |next| siblings_size = calculateDownwardsDependentSizes(next);
    for (siblings_size) |*elem, i|
        elem.* += block.computed_size[i];
    return siblings_size;
}

fn solveViolations(block: *Block) void {
    _ = block;
    // 4. (Pre-order) Solve violations. For each level in the hierarchy, this will verify that the children do not extend past the boundaries of a given parent (unless explicitly allowed to do so; for example, in the case of a parent that is scrollable on the given axis), to the best of the algorithm’s ability. If there is a violation, it will take a proportion of each child widget’s size (on the given axis) proportional to both the size of the violation, and (1-strictness), where strictness is that specified in the semantic size on the child widget for the given axis.
}

fn computeRelativePositions(block: *Block, position: [Axis.len]f32) void {
    for (block.computed_rel_position) |*computed_rel_position, i|
        computed_rel_position.* = position[i];

    var next_position = position;
    if (block.parent) |parent|
        next_position[@enumToInt(parent.layout_axis)] += block.computed_size[@enumToInt(parent.layout_axis)];

    const parent_rect = if (block.parent) |parent| parent.rect else rl.Rectangle.init(0, 0, 0, 0);
    block.rect.x = parent_rect.x + block.computed_rel_position[0];
    block.rect.y = parent_rect.y + block.computed_rel_position[1];
    block.rect.width = block.computed_size[0];
    block.rect.height = block.computed_size[1];

    if (block.first) |first| computeRelativePositions(first, std.mem.zeroes([Axis.len]f32));
    if (block.next) |next| computeRelativePositions(next, next_position);
}
