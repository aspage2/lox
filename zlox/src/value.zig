const inst = @import("inst.zig");
const std = @import("std");

pub const ValType = enum {
    Bool,
    Number,
    Nil,
    Obj,
};

pub const ValueError = error{
    UnexpectedType,
};

pub const Value = union(ValType) {
    Bool: bool,
    Number: f32,
    Nil: void,
    Obj: *Obj,

    pub fn expectType(self: Value, comptime typ: ValType) ?std.meta.fieldInfo(Value, typ).type {
        return switch (self) {
            inline else => |val, t| {
                if (t == typ) return val;
                return null;
            },
        };
    }

    pub fn isObjType(self: Value, comptime typ: ObjType) bool {
        return switch (self) {
            .Obj => |o| std.meta.activeTag(o) == typ,
            else => false,
        };
    }

    pub fn isFalsey(self: Value) bool {
        return switch (self) {
            .Nil => true,
            .Bool => |b| !b,
            else => false,
        };
    }

    pub fn equals(self: Value, other: Value) bool {
        const myType = std.meta.activeTag(self);
        const otherType = std.meta.activeTag(other);

        if (myType != otherType) return false;

        return switch (myType) {
            .Bool => self.Bool == other.Bool,
            .Nil => true,
            .Number => self.Number == other.Number,
            .Obj => self.Obj.equals(other.Obj),
        };
    }
};

pub fn printValue(val: Value) void {
    switch (val) {
        .Nil => std.debug.print("NIL", .{}),
        .Number => |n| std.debug.print("{d}", .{n}),
        .Bool => |b| std.debug.print("{any}", .{b}),
        .Obj => |o| printObject(o),
    }
}

pub fn printObject(obj: *const Obj) void {
    switch (obj.inst) {
        .String => |s| std.debug.print("\"{s}\"", .{s}),
        .Func => |f| f.print(),
    }
}

// Heap-allocated value types

pub const ObjType = enum(u8) {
    String,
    Func,
};

pub const SpecificObj = union(ObjType) {
    String: StringObj,
    Func: *FuncObj,
};

pub const Obj = struct {
    inst: SpecificObj,

    next: ?*Obj,

    fn equals(self: *Obj, other: *Obj) bool {
        switch (self.inst) {
            .String => |s| return std.mem.eql(u8, s, other.inst.String),
            .Func => return false,
        }
    }
};

pub const StringObj = []const u8;

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

    pub fn make(self: *StringTable, str: []const u8) !StringObj {
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

pub const FuncObj = struct {
    arity: u8,
    chunk: inst.Chunk,
    name: ?StringObj,

    pub fn sentinelFunction(alloc: std.mem.Allocator) !*FuncObj {
        return FuncObj.init(alloc, null, 0);
    }

    pub fn init(alloc: std.mem.Allocator, name: ?StringObj, arity: u8) !*FuncObj {
        const ret = try alloc.create(FuncObj);
        ret.arity = arity;
        ret.name = name;
        ret.chunk = try .init(alloc);
        return ret;
    }

    pub fn deinit(self: *FuncObj) void {
        self.chunk.deinit();
    }

    fn print(self: *FuncObj) void {
        if (self.name) |n| {
            std.debug.print("<func {s}>", .{n});
        } else {
            std.debug.print("<script>", .{});
        }
    }
};
