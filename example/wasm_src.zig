const std = @import("std");

extern "libtest" fn add(a: i32, b: i32, mul: *i32) i32;

extern "libtest" fn getArgv0(str_buf: [*]u8, max_len: u32) u32;

const max_arg_size = 256;

export fn allocBytes(size: u32) [*]u8 {
    var mem = std.heap.page_allocator.alloc(u8, @intCast(usize, size)) catch {
        std.debug.panic("Memory allocation failed!\n", .{});
    };
    for (mem) |*v, i| v.* = @intCast(u8, i);
    return mem.ptr;
}

export fn printStringZ(str: ?[*:0]const u8) void {
    std.debug.warn("printStringZ: ", .{});
    if (str) |s| {
        std.debug.warn("\"{s}\"\n", .{std.mem.span(str)});
    } else {
        std.debug.warn("null\n", .{});
    }
}

export fn addFive(num: i32) i32 {
    return num + 5;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var a = &arena.allocator;

    const a1 = 2;
    const a2 = 6;

    var mul_res: i32 = 0;
    const add_res = add(a1, a2, &mul_res);

    std.debug.warn("{d} + {d} = {d} (multiplied, it's {d}!)\n", .{ a1, a2, add_res, mul_res });

    var buf = try a.alloc(u8, max_arg_size);
    var written = getArgv0(buf.ptr, buf.len);
    if (written != 0) {
        std.debug.warn("Got string {s}!\n", .{buf[0..@intCast(usize, written)]});
    } else {
        std.debug.warn("Failed to write string! No bytes written.", .{});
    }
}
