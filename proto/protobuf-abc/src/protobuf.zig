const std = @import("std");
const StructField = std.builtin.Type.StructField;
const isIntegral = std.meta.trait.isIntegral;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const base64 = std.base64;
const base64Errors = std.base64.Error;
const ParseFromValueError = std.json.ParseFromValueError;

const Io = std.Io;

const log = std.log.scoped(.zig_protobuf);

// common definitions

const ArrayList = std.ArrayList;

/// Type of encoding for a Varint value.
const VarintType = enum { Simple, ZigZagOptimized };

pub const DecodingError = error{ NotEnoughData, InvalidInput };

pub const UnionDecodingError = DecodingError || Allocator.Error;

pub const ManagedStringTag = enum { Owned, Const, Empty };
pub const json = std.json;

pub fn ProtobufMixins(comptime T: type) type {
    return struct {
        pub fn getCmdId(_: *const @This()) u16 {
            return if (@hasDecl(T, "cmd_id")) T.cmd_id else 0;
        }

        pub fn encode(this: *const @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const self: *const T = @alignCast(@fieldParentPtr("pb", this));
            return encodeMessage(self.*, writer);
        }

        pub fn encodingLength(this: *const @This()) usize {
            const self: *const T = @alignCast(@fieldParentPtr("pb", this));
            return messageEncodingLength(self.*);
        }

        pub fn deinit(this: *const @This(), allocator: Allocator) void {
            const self: *const T = @alignCast(@fieldParentPtr("pb", this));
            return deinitializeMessage(self.*, allocator);
        }

        pub fn dupe(this: *const @This(), allocator: Allocator) Allocator.Error!@This() {
            const self: *const T = @alignCast(@fieldParentPtr("pb", this));
            return dupeMessage(T, self.*, allocator);
        }
    };
}

/// This structure is used by ManagedStruct to hold a T allocated.
fn AllocatedStruct(T: type) type {
    return struct {
        allocator: Allocator,
        v: *T,

        const Self = @This();

        /// Frees any allocated memory associated with the managed struct
        pub fn deinit(self: Self) void {
            self.v.deinit();
            self.allocator.destroy(self.v);
        }

        /// Initializes a new managed struct with the given allocator
        pub fn init(allocator: Allocator) !Self {
            const v = Self{ .allocator = allocator, .v = try allocator.create(T) };
            v.v.* = .{};
            return v;
        }
    };
}

pub const AllocatedString = struct { allocator: Allocator, str: []const u8 };

pub const ManagedString = union(ManagedStringTag) {
    Owned: AllocatedString,
    Const: []const u8,
    Empty,

    /// copies the provided string using the allocator. the `src` parameter should be freed by the caller
    pub fn copy(str: []const u8, allocator: Allocator) Allocator.Error!ManagedString {
        return ManagedString{ .Owned = AllocatedString{ .str = try allocator.dupe(u8, str), .allocator = allocator } };
    }

    /// moves the ownership of the string to the message. the caller MUST NOT free the provided string
    pub fn move(str: []const u8, allocator: Allocator) ManagedString {
        return ManagedString{ .Owned = AllocatedString{ .str = str, .allocator = allocator } };
    }

    /// creates a static string from a compile time const
    pub fn static(comptime str: []const u8) ManagedString {
        return ManagedString{ .Const = str };
    }

    /// creates a static string that will not be released by calling .deinit()
    pub fn managed(str: []const u8) ManagedString {
        return ManagedString{ .Const = str };
    }

    /// Returns true if the string is empty
    pub fn isEmpty(self: ManagedString) bool {
        return self.getSlice().len == 0;
    }

    /// Returns the underlying string slice
    pub fn getSlice(self: ManagedString) []const u8 {
        switch (self) {
            .Owned => |alloc_str| return alloc_str.str,
            .Const => |slice| return slice,
            .Empty => return "",
        }
    }

    /// Creates a deep copy of the managed string using the provided allocator
    pub fn dupe(self: ManagedString, allocator: Allocator) Allocator.Error!ManagedString {
        switch (self) {
            .Owned => |alloc_str| if (alloc_str.str.len == 0) {
                return .Empty;
            } else {
                return copy(alloc_str.str, allocator);
            },
            .Const, .Empty => return self,
        }
    }

    /// Frees any allocated memory associated with the managed string
    pub fn deinit(self: ManagedString) void {
        switch (self) {
            .Owned => |alloc_str| {
                alloc_str.allocator.free(alloc_str.str);
            },
            .Const, .Empty => {},
        }
    }

    // This method is used by std.json
    // internally for deserialization. DO NOT RENAME!
    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) !ManagedString {
        const string = try json.innerParse([]const u8, allocator, source, options);
        return ManagedString.copy(string, allocator);
    }

    // This method is used by std.json
    // internally for serialization. DO NOT RENAME!
    pub fn jsonStringify(self: *const ManagedString, jws: anytype) !void {
        try jws.write(self.getSlice());
    }
};

pub const ManagedStructTag = enum { Owned, Borrowed };

/// Creates a managed struct type that can either own or borrow an instance of type T.
/// This type provides memory management and lifecycle control for protobuf message structs.
/// This type is only generated by the protobuf compiler when there are self-referencing fields in the message.
pub fn ManagedStruct(T: type) type {
    return union(ManagedStructTag) {
        const Self = @This();
        const UnderlyingType = T;
        const AllocatedType = AllocatedStruct(T);

        Owned: AllocatedType,
        Borrowed: *T,

        /// This const's only purpose is to identify properly ManagedStructs.
        const isZigProtobufManagedStruct = true;

        /// Creates a ManagedStruct.Borrowed instance that has a pointer to an existing T, but do not take ownership of its memory.
        ///
        /// This means that a call to deinit on this instance will not free the memory associated with it. The original T's deinit() function must be called for that.
        pub fn managed(p: *T) Self {
            return Self{ .Borrowed = p };
        }

        /// Move the ownership of the pointer p and the allocator that allocated the T pointed by p to a new ManagedStruct.Owned instance.
        ///
        /// This means that a call to deinit on this instance will free the memory associated with it.
        pub fn move(p: *T, allocator: Allocator) Self {
            return Self{ .Owned = AllocatedType{ .allocator = allocator, .v = p } };
        }

        /// Frees any allocated memory (if any) associated with the managed struct
        pub fn deinit(self: Self) void {
            switch (self) {
                .Owned => |it| {
                    it.deinit();
                },
                .Borrowed => {},
            }
        }

        /// Creates a new Managestruct.Owned instance using the allocator provided.
        pub fn init(allocator: Allocator) !Self {
            return Self{ .Owned = try AllocatedType.init(allocator) };
        }

        pub fn get(self: Self) T {
            return switch (self) {
                .Borrowed => self.Borrowed.*,
                .Owned => |it| it.v.*,
            };
        }

        pub fn getPointer(self: *Self) *T {
            return switch (self.*) {
                .Borrowed => |it| it,
                .Owned => |*it| it.v,
            };
        }
    };
}

// this has to be inlined else managedStruct functions resolution breaks.
inline fn isZigProtobufManagedStruct(T: type) bool {
    return @hasDecl(T, "isZigProtobufManagedStruct");
}

/// Enum describing the different field types available.
pub const FieldTypeTag = enum { Varint, FixedInt, SubMessage, String, Bytes, List, PackedList, OneOf };

/// Enum describing how much bits a FixedInt will use.
pub const FixedSize = enum(u3) { I64 = 1, I32 = 5 };

/// Enum describing the content type of a repeated field.
pub const ListTypeTag = enum {
    Varint,
    String,
    Bytes,
    FixedInt,
    SubMessage,
};

/// Tagged union for repeated fields, giving the details of the underlying type.
pub const ListType = union(ListTypeTag) {
    Varint: VarintType,
    String,
    Bytes,
    FixedInt: FixedSize,
    SubMessage,
};

/// Main tagged union holding the details of any field type.
pub const FieldType = union(FieldTypeTag) {
    Varint: VarintType,
    FixedInt: FixedSize,
    SubMessage,
    String,
    Bytes,
    List: ListType,
    PackedList: ListType,
    OneOf: type,

    /// Returns the wire type of a field. See https://developers.google.com/protocol-buffers/docs/encoding#structure
    pub fn getWireValue(comptime ftype: FieldType) u3 {
        return switch (ftype) {
            .Varint => 0,
            .FixedInt => |size| @intFromEnum(size),
            .String, .SubMessage, .PackedList, .Bytes => 2,
            .List => |inner| switch (inner) {
                .Varint => 0,
                .FixedInt => |size| @intFromEnum(size),
                .String, .SubMessage, .Bytes => 2,
            },
            .OneOf => @compileError("Shouldn't pass a .OneOf field to this function here."),
        };
    }
};

/// Structure describing a field. Most of the relevant informations are
/// In the FieldType data. Tag is optional as OneOf fields are "virtual" fields.
pub const FieldDescriptor = struct {
    field_number: ?u32,
    xor_const: ?u16,
    ftype: FieldType,
};

/// Helper function to build a FieldDescriptor. Makes code clearer, mostly.
pub fn fd(comptime field_number: ?u32, comptime xor_const: ?u16, comptime ftype: FieldType) FieldDescriptor {
    return FieldDescriptor{
        .field_number = field_number,
        .xor_const = xor_const,
        .ftype = ftype,
    };
}

// encoding

/// Appends an unsigned varint value.
/// Awaits a u64 value as it's the biggest unsigned varint possible,
// so anything can be cast to it by definition
fn writeRawVarInt(writer: *Io.Writer, value: u64) Io.Writer.Error!void {
    var copy = value;
    while (copy > 0x7F) {
        try writer.writeByte(0x80 + @as(u8, @intCast(copy & 0x7F)));
        copy = copy >> 7;
    }
    try writer.writeByte(@as(u8, @intCast(copy & 0x7F)));
}

fn zigZagInteger(int: anytype, xor_const: ?u16) u64 {
    const type_of_val = @TypeOf(int);
    var to_int64: i64 = switch (type_of_val) {
        i32 => @intCast(int),
        i64 => int,
        else => @compileError("should not be here"),
    };

    if (xor_const) |xor| to_int64 ^= xor;

    const calc = (to_int64 << 1) ^ (to_int64 >> 63);
    return @bitCast(calc);
}

/// Appends a varint to the pb array.
/// Mostly does the required transformations to use append_raw_varint
/// after making the value some kind of unsigned value.
fn writeAsVarInt(writer: *Io.Writer, int: anytype, comptime xor_const: ?u16, comptime varint_type: VarintType) Io.Writer.Error!void {
    const type_of_val = @TypeOf(int);
    const val: u64 = blk: {
        switch (@typeInfo(type_of_val).int.signedness) {
            .signed => {
                switch (varint_type) {
                    .ZigZagOptimized => {
                        break :blk zigZagInteger(int, xor_const);
                    },
                    .Simple => {
                        var to_int64: u64 = @bitCast(@as(i64, @intCast(int)));
                        if (xor_const) |xor| to_int64 ^= xor;
                        break :blk to_int64;
                    },
                }
            },
            .unsigned => {
                var to_int64: u64 = @as(u64, @intCast(int));
                if (xor_const) |xor| to_int64 ^= xor;
                break :blk to_int64;
            },
        }
    };

    try writeRawVarInt(writer, val);
}

fn writeVarInt(writer: *Io.Writer, value: anytype, comptime xor_const: ?u16, comptime varint_type: VarintType) Io.Writer.Error!void {
    switch (@typeInfo(@TypeOf(value))) {
        .@"enum" => try writeAsVarInt(writer, @as(i32, @intFromEnum(value)), xor_const, varint_type),
        .bool => try writeAsVarInt(writer, @as(u8, if (value) 1 else 0), xor_const, varint_type),
        .int => try writeAsVarInt(writer, value, xor_const, varint_type),
        else => @compileError("Should not pass a value of type " ++ @typeInfo(@TypeOf(value)) ++ "here"),
    }
}

fn writeFixedInt(writer: *Io.Writer, value: anytype) Io.Writer.Error!void {
    // NOTE: currently none of the fixed-sized types are getting xored.
    // If it's needed, should be added here.

    const bitsize = @bitSizeOf(@TypeOf(value));

    var as_unsigned_int = switch (@TypeOf(value)) {
        f32, f64, i32, i64 => @as(std.meta.Int(.unsigned, bitsize), @bitCast(value)),
        u32, u64, u8 => @as(u64, value),
        else => @compileError("Invalid type for append_fixed"),
    };

    var index: usize = 0;

    while (index < (bitsize / 8)) : (index += 1) {
        try writer.writeByte(@as(u8, @truncate(as_unsigned_int)));
        as_unsigned_int = as_unsigned_int >> 8;
    }
}

/// Appends a submessage to the array.
/// Recursively calls encodeInternal.
fn writeSubMessage(writer: *Io.Writer, value: anytype) Io.Writer.Error!void {
    const size_encoded = messageEncodingLength(value);
    try writeAsVarInt(writer, size_encoded, null, .Simple);
    try encodeInternal(writer, value);
}

/// Simple appending of a list of bytes.
fn writeString(writer: *Io.Writer, value: ManagedString) Io.Writer.Error!void {
    const slice = value.getSlice();
    try writeAsVarInt(writer, slice.len, null, .Simple);
    try writer.writeAll(slice);
}

/// simple appending of a list of fixed-size data.
fn writeFixedIntList(writer: *Io.Writer, comptime field: FieldDescriptor, value_list: anytype) Io.Writer.Error!void {
    if (value_list.items.len > 0) {
        // first append the tag for the field descriptor
        try writeTag(writer, field);

        // calculate the length of packed list
        const len = (@bitSizeOf(std.meta.Elem(@TypeOf(value_list.items))) / 8) * value_list.items.len;

        // write length and elements
        try writeAsVarInt(writer, len, null, .Simple);
        for (value_list.items) |item| {
            try writeFixedInt(writer, item);
        }
    }
}

fn writeVarIntListPacked(writer: *Io.Writer, value_list: anytype, comptime field: FieldDescriptor, comptime varint_type: VarintType) Io.Writer.Error!void {
    if (value_list.items.len > 0) {
        try writeTag(writer, field);
        var len: usize = 0;
        for (value_list.items) |item| len += varIntLength(item, varint_type, null);
        try writeAsVarInt(writer, len, null, .Simple);

        for (value_list.items) |item| try writeVarInt(writer, item, null, varint_type);
    }
}

fn writeSubMessageList(writer: *Io.Writer, comptime field: FieldDescriptor, value_list: anytype) Io.Writer.Error!void {
    for (value_list.items) |item| {
        try writeTag(writer, field);
        try writeSubMessage(writer, item);
    }
}

fn writeTag(writer: *Io.Writer, comptime field: FieldDescriptor) Io.Writer.Error!void {
    const tag_value = (field.field_number.? << 3) | field.ftype.getWireValue();
    try writeVarInt(writer, tag_value, null, .Simple);
}

fn varIntLength(value: anytype, comptime varint_type: VarintType, comptime xor_const: ?u16) usize {
    const int = switch (@typeInfo(@TypeOf(value))) {
        .@"enum" => @intFromEnum(value),
        .int => value,
        .bool => return 1,
        else => @compileError("invalid type for varint specified: " ++ @typeName(@TypeOf(value))),
    };

    const type_of_val = @TypeOf(int);

    var val: u64 = blk: {
        switch (@typeInfo(type_of_val).int.signedness) {
            .signed => {
                switch (varint_type) {
                    .ZigZagOptimized => {
                        break :blk zigZagInteger(int, xor_const);
                    },
                    .Simple => {
                        var to_int64: u64 = @bitCast(@as(i64, @intCast(int)));
                        if (xor_const) |xor| to_int64 ^= xor;
                        break :blk to_int64;
                    },
                }
            },
            .unsigned => {
                var to_int64: u64 = @as(u64, @intCast(int));
                if (xor_const) |xor| to_int64 ^= xor;
                break :blk to_int64;
            },
        }
    };

    var total_len: usize = 0;
    while (val > 0x7F) {
        total_len += 1;
        val >>= 7;
    }

    return total_len + 1;
}

fn fixedIntLength(value: anytype) usize {
    return @bitSizeOf(@TypeOf(value)) / 8;
}

fn fieldEncodingLength(comptime field: FieldDescriptor, value: anytype, force_encoded: bool) usize {
    const tag = (field.field_number.? << 3) | field.ftype.getWireValue();
    const is_default_scalar_value = switch (@typeInfo(@TypeOf(value))) {
        .optional => value == null,
        // as per protobuf spec, the first element of the enums must be 0 and it is the default value
        .@"enum" => @intFromEnum(value) == 0,
        else => switch (@TypeOf(value)) {
            bool => value == false,
            i32, u32, i64, u64, f32, f64 => value == 0,
            ManagedString => value.isEmpty(),
            else => false,
        },
    };

    return switch (field.ftype) {
        .Varint => |varint_type| if (!is_default_scalar_value or force_encoded) varIntLength(tag, .Simple, null) + varIntLength(value, varint_type, field.xor_const) else 0,
        .FixedInt => if (!is_default_scalar_value or force_encoded) varIntLength(tag, .Simple, null) + fixedIntLength(value) else 0,
        .SubMessage => {
            const msg_len = messageEncodingLength(value);
            return varIntLength(tag, .Simple, null) + msg_len + varIntLength(msg_len, .Simple, null);
        },
        .String, .Bytes => if (!is_default_scalar_value or force_encoded) varIntLength(tag, .Simple, null) + varIntLength(value.getSlice().len, .Simple, null) + value.getSlice().len else 0,
        .PackedList => |list_type| {
            if (value.items.len != 0) {
                switch (list_type) {
                    .FixedInt => {
                        const content_len: usize = (@bitSizeOf(std.meta.Elem(@TypeOf(value.items))) / 8) * value.items.len;
                        return varIntLength(tag, .Simple, null) + content_len + varIntLength(content_len, .Simple, null);
                    },
                    .Varint => |varint_type| {
                        var content_len: usize = 0;
                        for (value.items) |int| content_len += varIntLength(int, varint_type, null);

                        return varIntLength(tag, .Simple, null) + content_len + varIntLength(content_len, .Simple, null);
                    },
                    .String, .Bytes => @compileError("byte arrays are not suitable for PackedLists."),
                    .SubMessage => @compileError("submessages are not suitable for PackedLists."),
                }
            } else {
                return 0;
            }
        },
        .List => |list_type| {
            if (value.items.len != 0) {
                switch (list_type) {
                    .FixedInt => {
                        return value.items.len * (varIntLength(tag, .Simple, null) + (@bitSizeOf(std.meta.Elem(@TypeOf(value.items))) / 8));
                    },
                    .SubMessage => {
                        var len: usize = value.items.len * varIntLength(tag, .Simple, null);
                        for (value.items) |item| {
                            const message_len = messageEncodingLength(item);
                            len += varIntLength(message_len, .Simple, null);
                            len += message_len;
                        }

                        return len;
                    },
                    .String, .Bytes => {
                        var len: usize = value.items.len * varIntLength(tag, .Simple, null);
                        for (value.items) |item| len += varIntLength(item.getSlice().len, .Simple, null) + item.getSlice().len;

                        return len;
                    },
                    .Varint => |varint_type| {
                        var len: usize = value.items.len * varIntLength(tag, .Simple, null);
                        for (value.items) |item| len += varIntLength(item, varint_type, null);

                        return len;
                    },
                }
            } else {
                return 0;
            }
        },
        .OneOf => |union_type| {
            // iterate over union tags until one matches `active_union_tag` and then use the comptime information to append the value
            const active_union_tag = @tagName(value);
            inline for (@typeInfo(@TypeOf(union_type._union_desc)).@"struct".fields) |union_field| {
                if (std.mem.eql(u8, union_field.name, active_union_tag)) {
                    return fieldEncodingLength(@field(union_type._union_desc, union_field.name), @field(value, union_field.name), force_encoded);
                }
            }
        },
    };
}

/// Appends a value to the pb buffer. Starts by appending the tag, then a comptime switch
/// routes the code to the correct type of data to append.
///
/// force_append is set to true if the field needs to be appended regardless of having the default value.
///   it is used when an optional int/bool with value zero need to be encoded. usually value==0 are not written, but optionals
///   require its presence to differentiate 0 from "null"
fn writeField(writer: *Io.Writer, comptime field: FieldDescriptor, value: anytype, comptime force_append: bool) Io.Writer.Error!void {

    // TODO: review semantics of default-value in regards to wire protocol
    const is_default_scalar_value = switch (@typeInfo(@TypeOf(value))) {
        .optional => value == null,
        // as per protobuf spec, the first element of the enums must be 0 and it is the default value
        .@"enum" => @intFromEnum(value) == 0,
        else => switch (@TypeOf(value)) {
            bool => value == false,
            i32, u32, i64, u64, f32, f64 => value == 0,
            ManagedString => value.isEmpty(),
            else => false,
        },
    };

    switch (field.ftype) {
        .Varint => |varint_type| {
            if (!is_default_scalar_value or force_append) {
                try writeTag(writer, field);
                try writeVarInt(writer, value, field.xor_const, varint_type);
            }
        },
        .FixedInt => {
            if (!is_default_scalar_value or force_append) {
                try writeTag(writer, field);
                try writeFixedInt(writer, value);
            }
        },
        .SubMessage => {
            if (!is_default_scalar_value or force_append) {
                try writeTag(writer, field);
                try writeSubMessage(writer, value);
            }
        },
        .String, .Bytes => {
            if (!is_default_scalar_value or force_append) {
                try writeTag(writer, field);
                try writeString(writer, value);
            }
        },
        .PackedList => |list_type| {
            switch (list_type) {
                .FixedInt => {
                    try writeFixedIntList(writer, field, value);
                },
                .Varint => |varint_type| {
                    try writeVarIntListPacked(writer, value, field, varint_type);
                },
                .String, .Bytes => @compileError("strings and bytes are not suitable for PackedLists."),
                .SubMessage => @compileError("submessages are not suitable for PackedLists."),
            }
        },
        .List => |list_type| {
            switch (list_type) {
                .FixedInt => {
                    for (value.items) |item| {
                        try writeTag(writer, field);
                        try writeFixedInt(writer, item);
                    }
                },
                .SubMessage => {
                    try writeSubMessageList(writer, field, value);
                },
                .String, .Bytes => {
                    for (value.items) |item| {
                        try writeTag(writer, field);
                        try writeString(writer, item);
                    }
                },
                .Varint => |varint_type| {
                    for (value.items) |item| {
                        try writeTag(writer, field);
                        try writeVarInt(writer, item, null, varint_type);
                    }
                },
            }
        },
        .OneOf => |union_type| {
            // iterate over union tags until one matches `active_union_tag` and then use the comptime information to append the value
            const active_union_tag = @tagName(value);
            inline for (@typeInfo(@TypeOf(union_type._union_desc)).@"struct".fields) |union_field| {
                if (std.mem.eql(u8, union_field.name, active_union_tag)) {
                    try writeField(writer, @field(union_type._union_desc, union_field.name), @field(value, union_field.name), force_append);
                }
            }
        },
    }
}

/// Internal function that decodes the descriptor information and struct fields
/// before passing them to the append function
fn encodeInternal(writer: *Io.Writer, data: anytype) Io.Writer.Error!void {
    const type_info_data = @typeInfo(@TypeOf(data));
    const data_type = switch (type_info_data) {
        .@"union" => |_| // ManagedStruct case
        @typeInfo(@TypeOf(data.Borrowed)).pointer.child,
        else => @TypeOf(data),
    };
    const field_list = @typeInfo(data_type).@"struct".fields;

    inline for (field_list) |field| {
        if (field.type == ProtobufMixins(@TypeOf(data))) continue;

        if (@typeInfo(field.type) == .optional) {
            const temp = getValue(@TypeOf(data), data);
            if (@field(temp, field.name)) |value| {
                try writeField(writer, @field(data_type._desc_table, field.name), value, true);
            }
        } else {
            const value = getValue(@TypeOf(data), data);
            try writeField(writer, @field(data_type._desc_table, field.name), @field(value, field.name), false);
        }
    }
}

pub fn messageEncodingLength(data: anytype) usize {
    const type_info_data = @typeInfo(@TypeOf(data));
    const data_type = switch (type_info_data) {
        .@"union" => |_| // ManagedStruct case
        @typeInfo(@TypeOf(data.Borrowed)).pointer.child,
        else => @TypeOf(data),
    };

    const field_list = @typeInfo(data_type).@"struct".fields;

    var len: usize = 0;
    inline for (field_list) |field| {
        if (field.type == ProtobufMixins(@TypeOf(data))) continue;

        if (@typeInfo(field.type) == .optional) {
            const temp = getValue(@TypeOf(data), data);
            if (@field(temp, field.name)) |value| {
                len += fieldEncodingLength(@field(data_type._desc_table, field.name), value, true);
            }
        } else {
            const value = getValue(@TypeOf(data), data);
            len += fieldEncodingLength(@field(data_type._desc_table, field.name), @field(value, field.name), false);
        }
    }

    return len;
}

/// Public encoding function, meant to be embdedded in generated structs
pub fn encodeMessage(data: anytype, writer: *Io.Writer) Io.Writer.Error!void {
    try encodeInternal(writer, data);
}

fn getDefaultFieldValue(comptime for_type: anytype) for_type {
    return switch (@typeInfo(for_type)) {
        .optional => null,
        // as per protobuf spec, the first element of the enums must be 0 and it is the default value
        .@"enum" => @as(for_type, @enumFromInt(0)),
        else => switch (for_type) {
            bool => false,
            i32, i64, i8, i16, u8, u32, u64, f32, f64 => 0,
            ManagedString => .Empty,
            else => undefined,
        },
    };
}

/// Generic function to deeply duplicate a message using a new allocator.
/// The original parameter is constant
pub fn dupeMessage(comptime T: type, original: T, allocator: Allocator) Allocator.Error!T {
    var result: T = undefined;

    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.type == ProtobufMixins(T)) continue;
        @field(result, field.name) = try dupeField(original, field.name, @field(T._desc_table, field.name).ftype, allocator);
    }

    return result;
}

/// Internal dupe function for a specific field
fn dupeField(original: anytype, comptime field_name: []const u8, comptime ftype: FieldType, allocator: Allocator) Allocator.Error!@TypeOf(@field(original, field_name)) {
    switch (ftype) {
        .Varint, .FixedInt => {
            return @field(original, field_name);
        },
        .List => |list_type| {
            const capacity = @field(original, field_name).items.len;
            var list = try @TypeOf(@field(original, field_name)).initCapacity(allocator, capacity);
            switch (list_type) {
                .SubMessage, .String => {
                    for (@field(original, field_name).items) |item| {
                        try list.append(allocator, try item.dupe(allocator));
                    }
                },
                .Varint, .Bytes, .FixedInt => {
                    for (@field(original, field_name).items) |item| {
                        try list.append(allocator, item);
                    }
                },
            }
            return list;
        },
        .PackedList => |_| {
            const capacity = @field(original, field_name).items.len;
            var list = try @TypeOf(@field(original, field_name)).initCapacity(allocator, capacity);

            for (@field(original, field_name).items) |item| {
                try list.append(allocator, item);
            }

            return list;
        },
        .SubMessage, .String, .Bytes => {
            switch (@typeInfo(@TypeOf(@field(original, field_name)))) {
                .optional => {
                    if (@field(original, field_name)) |val| {
                        return try val.dupe(allocator);
                    } else {
                        return null;
                    }
                },
                else => return try @field(original, field_name).dupe(allocator),
            }
        },
        .OneOf => |one_of| {
            // if the value is set, inline-iterate over the possible OneOfs
            if (@field(original, field_name)) |union_value| {
                const active = @tagName(union_value);
                inline for (@typeInfo(@TypeOf(one_of._union_desc)).@"struct".fields) |union_field| {
                    // and if one matches the actual tagName of the union
                    if (std.mem.eql(u8, union_field.name, active)) {
                        // deinit the current value
                        const value = try dupeField(union_value, union_field.name, @field(one_of._union_desc, union_field.name).ftype, allocator);

                        return @unionInit(one_of, union_field.name, value);
                    }
                }
            }
            return null;
        },
    }
}

/// Generic deinit function. Properly cleans any field required. Meant to be embedded in generated structs.
pub fn deinitializeMessage(data: anytype, allocator: Allocator) void {
    const T = @TypeOf(data);

    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.type == ProtobufMixins(T)) continue;

        deinitializeField(data, allocator, field.name, @field(T._desc_table, field.name).ftype);
    }
}

/// Internal deinit function for a specific field
fn deinitializeField(result: anytype, allocator: Allocator, comptime field_name: []const u8, comptime ftype: FieldType) void {
    switch (ftype) {
        .Varint, .FixedInt => {},
        .SubMessage => {
            switch (@typeInfo(@TypeOf(@field(result, field_name)))) {
                .optional => {
                    if (@field(result, field_name)) |*submessage| {
                        submessage.pb.deinit(allocator);
                    }
                },
                .@"struct" => @field(result, field_name).deinit(),
                else => @compileError("unreachable"),
            }
        },
        .List => |list_type| {
            switch (list_type) {
                .SubMessage => {
                    for (@field(result, field_name).items) |item| {
                        item.pb.deinit(allocator);
                    }
                },
                .String, .Bytes => {
                    for (@field(result, field_name).items) |*item| {
                        item.deinit();
                    }
                },
                .Varint, .FixedInt => {},
            }
            var list = @field(result, field_name);
            list.deinit(allocator);
        },
        .PackedList => |_| {
            var list = @field(result, field_name);
            list.deinit(allocator);
        },
        .String, .Bytes => {
            switch (@typeInfo(@TypeOf(@field(result, field_name)))) {
                .optional => {
                    if (@field(result, field_name)) |str| {
                        str.deinit();
                    }
                },
                else => @field(result, field_name).deinit(),
            }
        },
        .OneOf => |union_type| {
            // if the value is set, inline-iterate over the possible OneOfs
            if (@field(result, field_name)) |union_value| {
                const active = @tagName(union_value);
                inline for (@typeInfo(@TypeOf(union_type._union_desc)).@"struct".fields) |union_field| {
                    // and if one matches the actual tagName of the union
                    if (std.mem.eql(u8, union_field.name, active)) {
                        // deinit the current value
                        deinitializeField(union_value, allocator, union_field.name, @field(union_type._union_desc, union_field.name).ftype);
                    }
                }
            }
        },
    }
}

// decoding

/// Enum describing if described data is raw (<u64) data or a byte slice.
const ExtractedDataTag = enum {
    RawValue,
    Slice,
};

/// Union enclosing either a u64 raw value, or a byte slice.
const ExtractedData = union(ExtractedDataTag) { RawValue: u64, Slice: []const u8 };

/// Unit of extracted data from a stream
/// Please not that "tag" is supposed to be the full tag. See get_full_tag_value.
const Extracted = struct { tag: u32, field_number: u32, data: ExtractedData };

/// Decoded varint value generic type
fn DecodedVarint(comptime T: type) type {
    return struct {
        value: T,
        size: usize,
    };
}

/// Decodes a varint from a slice, to type T.
fn readVarInt(comptime T: type, input: []const u8) DecodingError!DecodedVarint(T) {
    var index: usize = 0;
    const len: usize = input.len;

    var shift: u32 = 0;
    var value: T = 0;
    while (true) {
        if (index >= len) return error.NotEnoughData;
        const b = input[index];
        if (shift >= @bitSizeOf(T)) {
            // We are casting more bits than the type can handle
            // It means the "@intCast(shift)" will throw a fatal error
            return error.InvalidInput;
        }
        value += (@as(T, input[index] & 0x7F)) << (@as(std.math.Log2Int(T), @intCast(shift)));
        index += 1;
        if (b >> 7 == 0) break;
        shift += 7;
    }

    return DecodedVarint(T){
        .value = value,
        .size = index,
    };
}

/// Decodes a fixed value to type T
fn readFixedInt(comptime T: type, slice: []const u8) T {
    const result_base: type = switch (@bitSizeOf(T)) {
        32 => u32,
        64 => u64,
        else => @compileError("can only manage 32 or 64 bit sizes"),
    };
    var result: result_base = 0;

    for (slice, 0..) |byte, index| {
        result += @as(result_base, @intCast(byte)) << (@as(std.math.Log2Int(result_base), @intCast(index * 8)));
    }

    return switch (T) {
        u32, u64 => result,
        else => @as(T, @bitCast(result)),
    };
}

fn FixedDecoderIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        const num_bytes = @divFloor(@bitSizeOf(T), 8);

        input: []const u8,
        current_index: usize = 0,

        fn next(self: *Self) ?T {
            if (self.current_index < self.input.len) {
                defer self.current_index += Self.num_bytes;
                return readFixedInt(T, self.input[self.current_index .. self.current_index + Self.num_bytes]);
            }
            return null;
        }
    };
}

fn VarintDecoderIterator(comptime T: type, comptime varint_type: VarintType) type {
    return struct {
        const Self = @This();

        input: []const u8,
        current_index: usize = 0,

        fn next(self: *Self) DecodingError!?T {
            if (self.current_index < self.input.len) {
                const raw_value = try readVarInt(u64, self.input[self.current_index..]);
                defer self.current_index += raw_value.size;
                return try unpackVarInt(T, varint_type, raw_value.value);
            }
            return null;
        }
    };
}

const LengthDelimitedDecoderIterator = struct {
    const Self = @This();

    input: []const u8,
    current_index: usize = 0,

    fn next(self: *Self) DecodingError!?[]const u8 {
        if (self.current_index < self.input.len) {
            const size = try readVarInt(u64, self.input[self.current_index..]);
            self.current_index += size.size;
            defer self.current_index += size.value;

            if (self.current_index > self.input.len or (self.current_index + size.value) > self.input.len) return error.NotEnoughData;

            return self.input[self.current_index .. self.current_index + size.value];
        }
        return null;
    }
};

/// "Tokenizer" of a byte slice to raw pb data.
pub const WireDecoderIterator = struct {
    input: []const u8,
    current_index: usize = 0,

    /// Attempts at decoding the next pb_buffer data.
    pub fn next(state: *WireDecoderIterator) DecodingError!?Extracted {
        if (state.current_index < state.input.len) {
            const tag_and_wire = try readVarInt(u32, state.input[state.current_index..]);
            state.current_index += tag_and_wire.size;
            const wire_type = tag_and_wire.value & 0b00000111;
            const data: ExtractedData = switch (wire_type) {
                0 => blk: { // VARINT
                    const varint = try readVarInt(u64, state.input[state.current_index..]);
                    state.current_index += varint.size;
                    break :blk ExtractedData{
                        .RawValue = varint.value,
                    };
                },
                1 => blk: { // 64BIT
                    const value = ExtractedData{ .RawValue = readFixedInt(u64, state.input[state.current_index .. state.current_index + 8]) };
                    state.current_index += 8;
                    break :blk value;
                },
                2 => blk: { // LEN PREFIXED MESSAGE
                    const size = try readVarInt(u32, state.input[state.current_index..]);
                    const start = (state.current_index + size.size);
                    const end = start + size.value;

                    if (state.input.len < start or state.input.len < end) {
                        return error.NotEnoughData;
                    }

                    const value = ExtractedData{ .Slice = state.input[start..end] };
                    state.current_index += size.value + size.size;
                    break :blk value;
                },
                3, 4 => { // SGROUP,EGROUP
                    return null;
                },
                5 => blk: { // 32BIT
                    const value = ExtractedData{ .RawValue = readFixedInt(u32, state.input[state.current_index .. state.current_index + 4]) };
                    state.current_index += 4;
                    break :blk value;
                },
                else => {
                    return error.InvalidInput;
                },
            };

            return Extracted{ .tag = tag_and_wire.value, .data = data, .field_number = tag_and_wire.value >> 3 };
        } else {
            return null;
        }
    }
};

fn unZigZagInteger(comptime T: type, raw: u64) DecodingError!T {
    comptime {
        switch (T) {
            i32, i64 => {},
            else => @compileError("should only pass i32 or i64 here"),
        }
    }

    const v: T = block: {
        var v = raw >> 1;
        if (raw & 0x1 != 0) {
            v = v ^ (~@as(u64, 0));
        }

        const bitcasted: i64 = @as(i64, @bitCast(v));

        break :block std.math.cast(T, bitcasted) orelse return DecodingError.InvalidInput;
    };

    return v;
}

test "decode zig zag test" {
    try testing.expectEqual(@as(i32, 0), unZigZagInteger(i32, 0));
    try testing.expectEqual(@as(i32, -1), unZigZagInteger(i32, 1));
    try testing.expectEqual(@as(i32, 1), unZigZagInteger(i32, 2));
    try testing.expectEqual(@as(i32, std.math.maxInt(i32)), unZigZagInteger(i32, 0xfffffffe));
    try testing.expectEqual(@as(i32, std.math.minInt(i32)), unZigZagInteger(i32, 0xffffffff));

    try testing.expectEqual(@as(i64, 0), unZigZagInteger(i64, 0));
    try testing.expectEqual(@as(i64, -1), unZigZagInteger(i64, 1));
    try testing.expectEqual(@as(i64, 1), unZigZagInteger(i64, 2));
    try testing.expectEqual(@as(i64, std.math.maxInt(i64)), unZigZagInteger(i64, 0xfffffffffffffffe));
    try testing.expectEqual(@as(i64, std.math.minInt(i64)), unZigZagInteger(i64, 0xffffffffffffffff));
}

/// Get a real varint of type T from a raw u64 data.
fn unpackVarInt(comptime T: type, comptime varint_type: VarintType, raw: u64) DecodingError!T {
    return switch (varint_type) {
        .ZigZagOptimized => switch (@typeInfo(T)) {
            .int => unZigZagInteger(T, raw),
            .@"enum" => std.meta.intToEnum(T, unZigZagInteger(i32, raw)) catch DecodingError.InvalidInput, // should never happen, enums are int32 simple?
            else => @compileError("Invalid type passed"),
        },
        .Simple => switch (@typeInfo(T)) {
            .int => switch (T) {
                u8, u16, u32, u64 => @as(T, @intCast(raw)),
                i64 => @as(T, @bitCast(raw)),
                i32 => std.math.cast(i32, @as(i64, @bitCast(raw))) orelse error.InvalidInput,
                else => @compileError("Invalid type " ++ @typeName(T) ++ " passed"),
            },
            .bool => raw != 0,
            .@"enum" => block: {
                const as_u32: u32 = std.math.cast(u32, raw) orelse return DecodingError.InvalidInput;
                break :block std.meta.intToEnum(T, @as(i32, @bitCast(as_u32))) catch DecodingError.InvalidInput;
            },
            else => @compileError("Invalid type " ++ @typeName(T) ++ " passed"),
        },
    };
}

/// Get a real fixed value of type T from a raw u64 value.
fn castFixedInt(comptime T: type, raw: u64) T {
    return switch (T) {
        i32, u32, f32 => @as(T, @bitCast(@as(std.meta.Int(.unsigned, @bitSizeOf(T)), @truncate(raw)))),
        i64, f64, u64 => @as(T, @bitCast(raw)),
        bool => raw != 0,
        else => @as(T, @bitCast(raw)),
    };
}

/// this function receives a slice of a message and decodes one by one the elements of the packet list until the slice is exhausted
fn readPackedList(slice: []const u8, comptime list_type: ListType, comptime T: type, array: *ArrayList(T), allocator: Allocator) UnionDecodingError!void {
    switch (list_type) {
        .FixedInt => {
            switch (T) {
                u32, i32, u64, i64, f32, f64 => {
                    var fixed_iterator = FixedDecoderIterator(T){ .input = slice };
                    while (fixed_iterator.next()) |value| {
                        try array.append(allocator, value);
                    }
                },
                else => @compileError("Type not accepted for FixedInt: " ++ @typeName(T)),
            }
        },
        .Varint => |varint_type| {
            var varint_iterator = VarintDecoderIterator(T, varint_type){ .input = slice };
            while (try varint_iterator.next()) |value| {
                try array.append(allocator, value);
            }
        },
        .String => {
            var varint_iterator = LengthDelimitedDecoderIterator{ .input = slice };
            while (try varint_iterator.next()) |value| {
                try array.append(allocator, try ManagedString.copy(value, allocator));
            }
        },
        .Bytes, .SubMessage =>
        // submessages are not suitable for packed lists yet, but the wire message can be malformed
        return error.InvalidInput,
    }
}

/// decode_value receives
fn readValue(comptime decoded_type: type, comptime ftype: FieldType, comptime xor_const: ?u16, extracted_data: Extracted, allocator: Allocator) UnionDecodingError!decoded_type {
    return switch (ftype) {
        .Varint => |varint_type| switch (extracted_data.data) {
            .RawValue => |value| {
                const decoded_value = try unpackVarInt(decoded_type, varint_type, value);
                return if (xor_const) |xor| decoded_value ^ xor else decoded_value;
            },
            .Slice => error.InvalidInput,
        },
        .FixedInt => switch (extracted_data.data) {
            .RawValue => |value| castFixedInt(decoded_type, value),
            .Slice => error.InvalidInput,
        },
        .SubMessage => switch (extracted_data.data) {
            .Slice => |slice| try decodeMessage(decoded_type, slice, allocator),
            .RawValue => error.InvalidInput,
        },
        .String, .Bytes => switch (extracted_data.data) {
            .Slice => |slice| try ManagedString.copy(slice, allocator),
            .RawValue => error.InvalidInput,
        },
        .List, .PackedList, .OneOf => {
            log.err("Invalid scalar type {any}\n", .{ftype});
            return error.InvalidInput;
        },
    };
}

fn readField(comptime T: type, comptime field_desc: FieldDescriptor, comptime field: StructField, result: *T, extracted_data: Extracted, allocator: Allocator) UnionDecodingError!void {
    switch (field_desc.ftype) {
        .Varint, .FixedInt, .SubMessage, .String, .Bytes => {
            // first try to release the current value
            deinitializeField(result, allocator, field.name, field_desc.ftype);

            // then apply the new value
            switch (@typeInfo(field.type)) {
                .optional => |optional| @field(result, field.name) = try readValue(optional.child, field_desc.ftype, field_desc.xor_const, extracted_data, allocator),
                else => @field(result, field.name) = try readValue(field.type, field_desc.ftype, field_desc.xor_const, extracted_data, allocator),
            }
        },
        .List, .PackedList => |list_type| {
            const child_type = @typeInfo(@TypeOf(@field(result, field.name).items)).pointer.child;

            switch (list_type) {
                .Varint => |varint_type| {
                    switch (extracted_data.data) {
                        .RawValue => |value| try @field(result, field.name).append(allocator, try unpackVarInt(child_type, varint_type, value)),
                        .Slice => |slice| try readPackedList(slice, list_type, child_type, &@field(result, field.name), allocator),
                    }
                },
                .FixedInt => |_| {
                    switch (extracted_data.data) {
                        .RawValue => |value| try @field(result, field.name).append(allocator, castFixedInt(child_type, value)),
                        .Slice => |slice| try readPackedList(slice, list_type, child_type, &@field(result, field.name), allocator),
                    }
                },
                .SubMessage => switch (extracted_data.data) {
                    .Slice => |slice| {
                        try @field(result, field.name).append(allocator, try decodeMessage(child_type, slice, allocator));
                    },
                    .RawValue => return error.InvalidInput,
                },
                .String, .Bytes => switch (extracted_data.data) {
                    .Slice => |slice| {
                        try @field(result, field.name).append(allocator, try ManagedString.copy(slice, allocator));
                    },
                    .RawValue => return error.InvalidInput,
                },
            }
        },
        .OneOf => |one_of| {
            // the following code:
            // 1. creates a compile time for iterating over all `one_of._union_desc` fields
            // 2. when a match is found, it creates the union value in the `field.name` property of the struct `result`. breaks the for at that point
            const desc_union = one_of._union_desc;
            inline for (@typeInfo(one_of).@"union".fields) |union_field| {
                const v = @field(desc_union, union_field.name);
                if (isTagKnown(v, extracted_data)) {
                    // deinit the current value of the enum to prevent leaks
                    deinitializeField(result, allocator, field.name, field_desc.ftype);

                    // and decode & assign the new value
                    const value = try readValue(union_field.type, v.ftype, v.xor_const, extracted_data, allocator);
                    @field(result, field.name) = @unionInit(one_of, union_field.name, value);
                }
            }
        },
    }
}

inline fn isTagKnown(comptime field_desc: FieldDescriptor, tag_to_check: Extracted) bool {
    if (field_desc.field_number) |field_number| {
        return field_number == tag_to_check.field_number;
    } else {
        const desc_union = field_desc.ftype.OneOf._union_desc;
        inline for (@typeInfo(@TypeOf(desc_union)).@"struct".fields) |union_field| {
            if (isTagKnown(@field(desc_union, union_field.name), tag_to_check)) {
                return true;
            }
        }
    }

    return false;
}

fn RootType(T: type) type {
    return if (isZigProtobufManagedStruct(T))
        T.UnderlyingType
    else
        return T;
}

fn initForDecode(T: type, allocator: Allocator) !T {
    return if (isZigProtobufManagedStruct(T))
        try T.init(allocator)
    else
        .{};
}

fn getPointer(T: type, instance: *T) *RootType(T) {
    return if (isZigProtobufManagedStruct(T))
        instance.getPointer()
    else
        instance;
}

fn getValue(T: type, instance: T) RootType(T) {
    return if (isZigProtobufManagedStruct(T))
        instance.get()
    else
        instance;
}

/// public decoding function meant to be embedded in message structures
/// Iterates over the input and try to fill the resulting structure accordingly.
pub fn decodeMessage(comptime T: type, input: []const u8, allocator: Allocator) UnionDecodingError!T {
    var result = try initForDecode(T, allocator);

    var iterator = WireDecoderIterator{ .input = input };

    while (try iterator.next()) |extracted_data| {
        const rootType = RootType(T);
        inline for (@typeInfo(rootType).@"struct".fields) |field| {
            if (field.type == ProtobufMixins(T)) continue;

            const v = @field(rootType._desc_table, field.name);
            if (isTagKnown(v, extracted_data)) {
                break try readField(rootType, v, field, getPointer(T, &result), extracted_data, allocator);
            }
        } else {
            log.debug("Unknown field received in {s} {any}\n", .{ @typeName(T), extracted_data.tag });
        }
    }

    return result;
}

fn freeAllocated(allocator: Allocator, token: json.Token) void {
    // Took from std.json source code since it was non-public one
    switch (token) {
        .allocated_number, .allocated_string => |slice| {
            allocator.free(slice);
        },
        else => {},
    }
}

fn fillDefaultStructValues(
    comptime T: type,
    r: *T,
    fields_seen: *[@typeInfo(T).@"struct".fields.len]bool,
) error{MissingField}!void {
    // Took from std.json source code since it was non-public one
    inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
        if (!fields_seen[i]) {
            if (field.defaultValue()) |default| {
                @field(r, field.name) = default;
            } else {
                return error.MissingField;
            }
        }
    }
}
