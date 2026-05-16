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
        .String => |s| std.debug.print("\"{s}\"", .{s.data}),
    }
}

// Heap-allocated value types

pub const ObjType = enum(u8) {
    String,
};

pub const SpecificObj = union(ObjType) {
    String: *StringObj,
};

pub const Obj = struct {
    inst: SpecificObj,

    next: ?*Obj,

    fn equals(self: *Obj, other: *Obj) bool {
        switch (self.inst) {
            .String => |s| {
                return s == other.inst.String;
            },
        }
    }
};

pub const StringObj = struct {
    data: []const u8,

    pub fn deinit(self: *StringObj, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
    }
};

pub const StringTable = struct {
    alloc: std.mem.Allocator,
    tbl: std.array_hash_map.String(*StringObj),

    pub fn init(alloc: std.mem.Allocator) !StringTable {
        return .{
            .alloc = alloc,
            .tbl = try .init(alloc, &.{}, &.{}),
        };
    }

    pub fn deinit(self: *StringTable) void {
        for (self.tbl.values()) |v| {
            self.alloc.free(v.data);
            self.alloc.destroy(v);
        }
    }

    pub fn make(self: *StringTable, str: []const u8) !*StringObj {
        if (self.tbl.get(str)) |ent| {
            return ent;
        }
        const sobj = try self.alloc.create(StringObj);
        sobj.data = try self.alloc.dupe(u8, str);
        try self.tbl.put(self.alloc, sobj.data, sobj);
        return sobj;
    }

    pub fn pprint(self: *StringTable) void {
        std.debug.print("<----STRING TABLE---->\n", .{});
        for (self.tbl.values()) |v| {
            std.debug.print("{*} {d:>6} {s}\n", .{ v.data.ptr, v.data.len, v.data });
        }
        std.debug.print("</---STRING TABLE---->\n", .{});
    }
};
