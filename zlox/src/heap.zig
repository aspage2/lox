/// The heap holds heap-allocated objects

const std = @import("std");
const value = @import("value.zig");

const Heap = @This();

alloc: std.mem.Allocator,
objects: std.ArrayList(value.Obj),
strings: StringTable = undefined,

pub fn init(alloc: std.mem.Allocator) !*Heap {
    var ret: *Heap = try alloc.create(Heap);
    ret.alloc = alloc;
    ret.objects = try .initCapacity(alloc, 16);
    ret.strings = try .init(alloc);
    return ret;
}

pub fn deinit(self: *Heap) void {
    for (self.objects.items) |o| switch (o) {
        .Func => |f| {
            f.deinit();
            self.alloc.destroy(f);
        },
        .NativeFn => |n| {
            self.alloc.destroy(n);
        },
        else => {
            std.debug.print("Not cleaning it up\n", .{});
        },
    };
    self.strings.deinit();
}

pub fn allocateString(self: *Heap, data: []const u8) !value.StringObj {
    const s = try self.strings.make(data);
    try self.objects.append(self.alloc, .{ .String = s });
    return s;
}

pub fn newFunction(self: *Heap) !*value.FuncObj {
    const func = try self.alloc.create(value.FuncObj);
    try self.objects.append(self.alloc, .{ .Func = func });
    func.name = null;
    func.arity = 0;
    func.chunk = try .init(self.alloc);
    return func;
}

pub fn newNative(self: *Heap, comptime name: []const u8, comptime impl: value.NativeObj.Impl) !*value.NativeObj {
    const n = try self.alloc.create(value.NativeObj);
    n.name = name;
    n.impl = impl;
    try self.objects.append(self.alloc, .{ .NativeFn = n});
    return n;
}

pub fn takeString(self: *Heap, alloc: std.mem.Allocator, data: []const u8) !value.StringObj {
    if (self.strings.tbl.getKey(data)) |k| {
        if (data.ptr == k.ptr and data.len == k.len) {
            return data;
        }
        alloc.free(data);
        return k;
    }
    const ret = try self.allocateString(data);
    alloc.free(data);
    return ret;
}

pub const StringTable = struct {
    alloc: std.mem.Allocator,
    tbl: std.array_hash_map.String(void),

    pub fn init(alloc: std.mem.Allocator) !StringTable {
        return .{
            .alloc = alloc,
            .tbl = try .init(alloc, &.{}, &.{}),
        };
    }

    pub fn deinit(self: *StringTable) void {
        for (self.tbl.keys()) |k| {
            self.alloc.free(k);
        }
        self.tbl.deinit(self.alloc);
    }

    pub fn make(self: *StringTable, str: value.StringObj) !value.StringObj {
        if (self.tbl.getKey(str)) |k| {
            return k;
        }
        const sobj = try self.alloc.dupe(u8, str);
        try self.tbl.put(self.alloc, sobj, {});
        return sobj;
    }
    
    pub fn pprint(self: *StringTable) void {
        std.debug.print("<----STRING TABLE---->\n", .{});
        for (self.tbl.keys()) |k| {
            std.debug.print("{*} {d:>6} {s}\n", .{ k.ptr, k.len, k });
        }
        std.debug.print("</---STRING TABLE---->\n", .{});
    }
};
