/// The heap holds heap-allocated objects
const std = @import("std");
const value = @import("value.zig");
const build_opts = @import("build_options");

const Heap = @This();

alloc: std.mem.Allocator,
objects: std.ArrayList(value.Obj),
strings: std.array_hash_map.String(*value.Obj),

pub fn init(alloc: std.mem.Allocator) !*Heap {
    var ret: *Heap = try alloc.create(Heap);
    ret.alloc = alloc;
    ret.objects = try .initCapacity(alloc, 16);
    ret.strings = .empty;
    return ret;
}

pub fn deinit(self: *Heap) void {
    for (self.objects.items) |o| switch (o.instance) {
        .Func => |f| {
            f.deinit();
            self.alloc.destroy(f);
        },
        .NativeFn => |n| {
            self.alloc.destroy(n);
        },
        .Closure => |c| {
            c.upvalues.deinit(self.alloc);
            self.alloc.destroy(c);
        },
        .Upvalue => |uv| self.alloc.destroy(uv),
        .String => {
            if (build_opts.lox_debug) {
                std.debug.print(
                    "Won't clean up string here because string table will",
                );
            }
        },
    };
    self.objects.deinit(self.alloc);
    for (self.strings.keys()) |k| {
        self.alloc.free(k);
    }
    self.strings.deinit(self.alloc);
}

fn addObject(self: *Heap, inst: anytype) !*value.Obj {
    try self.objects.append(self.alloc, .init(inst));
    return &self.objects.items[self.objects.items.len - 1];
}

/// Create a copy of the provided string in this heap.
pub fn allocateString(self: *Heap, data: []const u8) !*value.Obj { 
    const s = try self.strings.getOrPut(self.alloc, data);
    if (s.found_existing) return s.value_ptr.*;
    const dataCopy: value.StringObj = try self.alloc.dupe(u8, data);
    const o = try self.addObject(dataCopy);
    s.value_ptr.* = o;
    return o;
}

/// Take ownership of the heap-allocated string, freeing the
/// provided data and saving a copy in the heap.
///
/// data must have been allocated with the provided allocator.
pub fn takeString(self: *Heap, alloc: std.mem.Allocator, data: []const u8) !*value.Obj {
    if (self.strings.getEntry(data)) |kv| {
        const k = kv.key_ptr.*;
        if (data.ptr != k.ptr or data.len != k.len) {
            alloc.free(data);
        }
        return kv.value_ptr.*;
    }
    const ret = try self.allocateString(data);
    alloc.free(data);
    return ret;
}


pub fn newFunction(self: *Heap) !*value.Obj {
    const func = try self.alloc.create(value.FuncObj);
    func.name = null;
    func.arity = 0;
    func.chunk = try .init(self.alloc);
    func.upvalueCount = 0;
    return self.addObject(func);
}

pub fn newNative(self: *Heap, comptime name: []const u8, comptime impl: value.NativeObj.Impl) !*value.Obj {
    const n = try self.alloc.create(value.NativeObj);
    n.name = name;
    n.impl = impl;
    return self.addObject(n);
}

pub fn newClosure(self: *Heap, func: *value.FuncObj) !*value.Obj {
    const closure = try self.alloc.create(value.ClosureObj);
    closure.function = func;
    closure.upvalues = try .initCapacity(self.alloc, func.upvalueCount);

    for (0..closure.function.upvalueCount) |_| {
        closure.upvalues.appendAssumeCapacity(undefined);
    }

    return self.addObject(closure);
}

pub fn newUpvalue(self: *Heap, slot: *value.Value) !*value.Obj {
    const uv = try self.alloc.create(value.UpvalueObj);
    uv.location = slot;
    uv.next = null;
    uv.closedValue = .Nil;
    return self.addObject(uv);
}

pub fn pprint(self: *Heap) void {
    std.debug.print("<----STRING TABLE---->\n", .{});
    for (self.strings.keys()) |k| {
        std.debug.print("{*} {d:>6} {s}\n", .{ k.ptr, k.len, k });
    }
    std.debug.print("</---STRING TABLE---->\n", .{});
}

