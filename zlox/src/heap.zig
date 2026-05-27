/// The heap holds heap-allocated objects

const std = @import("std");
const value = @import("value.zig");

const Heap = @This();

objArena: std.heap.ArenaAllocator = undefined,
objAlloc: std.mem.Allocator = undefined,
strings: StringTable = undefined,

pub fn init(parent: std.mem.Allocator) !*Heap {
    var ret: *Heap = try parent.create(Heap);
    ret.objArena = .init(parent);
    ret.objAlloc = ret.objArena.allocator();
    ret.strings = try .init(parent);
    return ret;
}

pub fn deinit(self: *Heap) void {
    self.objArena.deinit();
    self.strings.deinit();
}

pub fn allocateObject(self: *Heap) !*value.Obj {
    return try self.objAlloc.create(value.Obj);
}

pub fn allocateString(self: *Heap, data: []const u8) !*value.Obj {
    const o = try self.allocateObject();
    o.inst = .{.String = try self.strings.make(data)};
    return o;
}

pub fn takeString(self: *Heap, alloc: std.mem.Allocator, data: []const u8) !*value.Obj {
    if (self.strings.tbl.getKey(data)) |k| {
        if (data.ptr == k.ptr and data.len == k.len) {
            const o = try self.allocateObject();
            o.inst = .{ .String = data };
            return o;
        }
        alloc.free(data);
        const o = try self.allocateObject();
        o.inst = .{ .String = k };
        return o;
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
