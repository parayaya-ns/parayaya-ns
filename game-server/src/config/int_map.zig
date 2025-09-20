// std.json.ArrayHashMap w/ built-in int keys parsing

const std = @import("std");
const Allocator = std.mem.Allocator;

const ParseOptions = std.json.ParseOptions;
const innerParse = std.json.innerParse;
const innerParseFromValue = std.json.innerParseFromValue;
const Value = std.json.Value;

pub fn IntMap(comptime Int: type, comptime T: type) type {
    return struct {
        map: std.AutoArrayHashMapUnmanaged(Int, T) = .empty,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            self.map.deinit(allocator);
        }

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !@This() {
            var map: std.AutoArrayHashMapUnmanaged(Int, T) = .empty;
            errdefer map.deinit(allocator);

            if (.object_begin != try source.next()) return error.UnexpectedToken;
            while (true) {
                const token = try source.nextAlloc(allocator, options.allocate.?);
                switch (token) {
                    inline .string, .allocated_string => |k| {
                        const int = std.fmt.parseInt(Int, k, 10) catch return error.InvalidNumber;
                        const gop = try map.getOrPut(allocator, int);
                        if (gop.found_existing) {
                            switch (options.duplicate_field_behavior) {
                                .use_first => {
                                    // Parse and ignore the redundant value.
                                    // We don't want to skip the value, because we want type checking.
                                    _ = try innerParse(T, allocator, source, options);
                                    continue;
                                },
                                .@"error" => return error.DuplicateField,
                                .use_last => {},
                            }
                        }
                        gop.value_ptr.* = try innerParse(T, allocator, source, options);
                    },
                    .object_end => break,
                    else => unreachable,
                }
            }
            return .{ .map = map };
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) !@This() {
            if (source != .object) return error.UnexpectedToken;

            var map: std.StringArrayHashMapUnmanaged(T) = .empty;
            errdefer map.deinit(allocator);

            var it = source.object.iterator();
            while (it.next()) |kv| {
                const int = std.fmt.parseInt(kv.key_ptr.*, Int, 10) catch return error.InvalidNumber;
                try map.put(allocator, int, try innerParseFromValue(T, allocator, kv.value_ptr.*, options));
            }
            return .{ .map = map };
        }

        pub fn jsonStringify(self: @This(), jws: anytype) !void {
            try jws.beginObject();
            var it = self.map.iterator();
            while (it.next()) |kv| {
                var num_str: [16]u8 = undefined;
                const len = std.fmt.printInt(&num_str, kv.key_ptr.*, 10, .upper, .{});

                try jws.objectField(num_str[0..len]);
                try jws.write(kv.value_ptr.*);
            }
            try jws.endObject();
        }
    };
}
