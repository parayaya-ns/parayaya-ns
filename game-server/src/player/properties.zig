const std = @import("std");
const Allocator = std.mem.Allocator;

/// 'Mixin'-like zero-sized-struct to be embedded in property containers.
/// Wraps the container functions.
pub fn PropertyMixin(comptime T: type) type {
    return struct {
        pub fn isChanged(mixin: *const @This()) bool {
            return isContainerChanged(T, @alignCast(@fieldParentPtr("property", mixin)));
        }

        pub fn resetChangeState(mixin: *@This()) void {
            resetContainerChangeState(T, @alignCast(@fieldParentPtr("property", mixin)));
        }
    };
}

fn isContainerChanged(comptime T: type, container: *const T) bool {
    inline for (std.meta.fields(T)) |field| {
        if (field.type == PropertyMixin(T)) continue;
        if (comptime std.meta.activeTag(@typeInfo(field.type)) != .@"struct") continue;

        if (@hasDecl(field.type, "isChanged")) {
            if (@field(container, field.name).isChanged()) return true;
        } else if (@hasField(field.type, "property")) {
            if (@field(container, field.name).property.isChanged()) return true;
        }
    }

    return false;
}

fn resetContainerChangeState(comptime T: type, container: *T) void {
    inline for (std.meta.fields(T)) |field| {
        if (field.type == PropertyMixin(T)) continue;
        if (comptime std.meta.activeTag(@typeInfo(field.type)) != .@"struct") continue;

        if (@hasDecl(field.type, "resetChangeState")) {
            @field(container, field.name).resetChangeState();
        } else if (@hasField(field.type, "property")) {
            @field(container, field.name).property.resetChangeState();
        }
    }
}

pub fn PropertyArrayHashMap(comptime Key: type, comptime Value: type) type {
    return struct {
        pub const empty: @This() = .{};

        map: std.AutoArrayHashMapUnmanaged(Key, Value) = .empty,
        changed_keys: std.ArrayList(Key) = .empty,

        pub fn deinit(this: *@This(), gpa: Allocator) void {
            this.map.deinit(gpa);
            this.changed_keys.deinit(gpa);
        }

        /// All the operations should be within the capacity
        /// Capacity is ensured to be at least of amount of entries in 'map'
        /// Re-allocations for 'changed_keys' are done in 'put' method.
        /// As far as you're pushing keys that exist in map you're fine. (Assuming you were using 'put' method all the time)
        pub fn pushChangedKey(this: *@This(), key: Key) void {
            if (std.mem.indexOfScalar(Key, this.changed_keys.items, key) != null) return;
            this.changed_keys.appendAssumeCapacity(key);
        }

        pub fn put(this: *@This(), gpa: Allocator, key: Key, value: Value) Allocator.Error!void {
            try this.map.put(gpa, key, value);
            try this.changed_keys.ensureTotalCapacity(gpa, this.map.count());

            this.pushChangedKey(key);
        }

        /// Returns the pointer to item by key for read-write operations.
        /// Pushes given key into the list of changed keys if entry exists.
        pub fn getPtr(this: *@This(), key: Key) ?*Value {
            if (this.map.getPtr(key)) |value| {
                this.pushChangedKey(key);
                return value;
            }

            return null;
        }

        /// Returns the const pointer to item by key for read-only operations.
        pub fn getConstPtr(this: *const @This(), key: Key) ?*const Value {
            return this.map.getPtr(key);
        }

        pub fn remove(this: *@This(), key: Key) ?@FieldType(@This(), "map").KV {
            if (this.map.fetchSwapRemove(key)) |kv| {
                if (std.mem.indexOfScalar(Key, this.changed_keys.items, key)) |i| this.changed_keys.swapRemove(i);
                return kv;
            }

            return null;
        }

        pub fn count(this: *const @This()) usize {
            return this.map.count();
        }

        pub fn contains(this: *const @This(), key: Key) bool {
            return this.map.contains(key);
        }

        /// 'Property' container API function
        pub fn isChanged(this: *const @This()) bool {
            return this.changed_keys.items.len != 0;
        }

        /// 'Property' container API function
        pub fn resetChangeState(this: *@This()) void {
            this.changed_keys.clearRetainingCapacity();
        }
    };
}

pub fn PropertyHashSet(comptime T: type) type {
    return struct {
        pub const empty: @This() = .{};

        map: std.AutoHashMapUnmanaged(T, void) = .empty,
        is_changed: bool = false,

        pub fn deinit(this: *@This(), gpa: Allocator) void {
            this.map.deinit(gpa);
        }

        /// Inserts the 'value' into the set.
        /// Returns true if the value wasn't present in the set before.
        pub fn put(this: *@This(), gpa: Allocator, value: T) Allocator.Error!bool {
            if (try this.map.fetchPut(gpa, value, {}) != null) return false;

            this.is_changed = true;
            return true;
        }

        pub fn count(this: *const @This()) usize {
            return this.map.count();
        }

        pub fn contains(this: *const @This(), value: T) bool {
            return this.map.contains(value);
        }

        pub fn iterate(this: *const @This()) std.AutoHashMapUnmanaged(T, void).KeyIterator {
            return this.map.keyIterator();
        }

        /// 'Property' container API function
        pub fn isChanged(this: *const @This()) bool {
            return this.is_changed;
        }

        /// 'Property' container API function
        pub fn resetChangeState(this: *@This()) void {
            this.is_changed = false;
        }
    };
}

pub fn Slice(comptime Elem: type) type {
    return struct {
        pub const empty: @This() = .{};

        slice: []const Elem = &.{},
        is_changed: bool = false,

        /// Frees the underlying slice.
        pub fn deinit(this: *@This(), gpa: Allocator) void {
            if (this.slice.len != 0) gpa.free(this.slice);
        }

        /// Clones the passed slice. Frees previous slice if it is not empty, assuming the same Allocator instance is passed.
        pub fn set(this: *@This(), gpa: Allocator, data: []const Elem) Allocator.Error!void {
            if (this.slice.len != 0) gpa.free(this.slice);
            this.slice = try gpa.dupe(Elem, data);
            this.is_changed = true;
        }

        pub fn isChanged(this: *const @This()) bool {
            return this.is_changed;
        }

        pub fn resetChangeState(this: *@This()) void {
            this.is_changed = false;
        }
    };
}

pub fn BasicType(comptime T: type) type {
    return packed struct {
        pub const default: @This() = .{};

        value: T = if (T == bool) false else 0,
        is_changed: bool = false,

        pub fn set(this: *@This(), value: T) void {
            this.value = value;
            this.is_changed = true;
        }

        pub fn isChanged(this: *const @This()) bool {
            return this.is_changed;
        }

        pub fn resetChangeState(this: *@This()) void {
            this.is_changed = false;
        }
    };
}
