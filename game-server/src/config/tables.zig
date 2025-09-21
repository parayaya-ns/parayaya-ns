const std = @import("std");
const IntMap = @import("int_map.zig").IntMap;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

pub const SpriteCommonConfig = struct {
    config_id: u32,
    b979298be2397c25: u32,
    ac1218e1cd7fc862: bool,
    a9dfde835e8fe4ef: AD61077CFCBEFAEA,
    f7df080da2483eda: AD61077CFCBEFAEA,
    bfc250af57dd31bd: AD61077CFCBEFAEA,
    ed8fa9cec8efef00: f32,
    eb772844ea861886: f32,
    ed876e103a129115: AD61077CFCBEFAEA,
    bc46d37711424dcf: []const u32,
    b7873d900545c3fb: []const SpriteRankConfig,
    aeac1dbc0086651f: u32,
    a041070e901885c3: u32,
    f5ed1423f389139b: E865F6F8B8B44C1E,
    baf26bd56cce102e: E865F6F8B8B44C1E,
    a0a7a6588b40bc66: E865F6F8B8B44C1E,
    bd06a3db9f7441ce: []const u32,
    f48a7f93ae859e1c: []const u32,
    a42119f3bd7469b2: []const u32,
    acb3f44f0c7f3e52: []const u32,
};

pub const SpriteRankConfig = struct {
    a9dfde835e8fe4ef: AD61077CFCBEFAEA,
    f5ed1423f389139b: E865F6F8B8B44C1E,
    e5ba8e59574183dd: u32,
    rank_up_cost: ?SpriteRankUpCost,
};

pub const TrainerCommonConfig = struct {
    config_id: u32,
    ee0cc585fcad587d: u32,
    rank_up_cost: IntMap(u32, TrainerRankUpCost),
    fbbc7a3e010c3647: []const ItemData,
    a3635dc9aae1e470: []const ItemData,
    aeac1dbc0086651f: u32,
    e363e64b722164aa: bool,
    ffba01e1e29ca03c: u32,
};

pub const TrainerRankUpCost = struct {
    rank_up_material: u32,
    rank_up_cost: u32,
};

pub const SpriteRankUpCost = struct {
    rank_up_material: u32,
    rank_up_cost: u32,
};

pub const ItemData = struct {
    fea482a8b1a301ab: u32,
    b30ed973daba6c56: u32,
};

pub const PlayerAvatarConfig = struct {
    config_id: u32,
    a9dfde835e8fe4ef: AD61077CFCBEFAEA,
    f2c496fff3d9a350: bool,
    ee677fcc5e2a0566: u32,
    f5ed1423f389139b: E865F6F8B8B44C1E,
    f7df080da2483eda: AD61077CFCBEFAEA,
    fc26520e2d611f2d: i32,
};

pub const AD61077CFCBEFAEA = struct {
    fd2e0e13663c8ae4: u64,
};

pub const E865F6F8B8B44C1E = struct {
    a211d069c8a848c9: u64,
};

pub const TeleportConfig = struct {
    config_id: u32,
    scene_id: u32,
    aed7c0e14465b543: u32,
    f5019db265ea7462: u32,
    position: Vector3,
    rotation: Vector3,
    ba69217151b3eda7: bool,
};

pub const Vector3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const TrainerCommonTableConfig = Table(TrainerCommonConfig, .config_id, "TrainerCommonTableConfig.json");
pub const PlayerAvatarTableConfig = Table(PlayerAvatarConfig, .config_id, "PlayerAvatarTableConfig.json");
pub const TeleportTable = Table(TeleportConfig, .config_id, "TeleportTable.json");
pub const SpriteCommonTable = Table(SpriteCommonConfig, .config_id, "SpriteCommonTable.json");

pub fn Table(
    comptime Config: type,
    comptime key_field: std.meta.FieldEnum(Config),
    comptime json_file_name: []const u8,
) type {
    return struct {
        const filename = json_file_name;
        const Key = @FieldType(Config, @tagName(key_field));

        items: []const Config,
        index_map: std.AutoHashMapUnmanaged(@This().Key, usize),

        pub fn loadFromJson(allocator: Allocator, json_str: []const u8, json_options: std.json.ParseOptions) !@This() {
            var table: @This() = undefined;
            table.items = try std.json.parseFromSliceLeaky([]const Config, allocator, json_str, json_options);

            table.index_map = .empty;
            try table.index_map.ensureTotalCapacity(allocator, @intCast(table.items.len));

            for (table.items, 0..) |config, index| {
                table.index_map.putAssumeCapacity(@field(config, @tagName(key_field)), index);
            }

            return table;
        }

        pub fn get(table: *const @This(), key: @This().Key) ?*const Config {
            return if (table.index_map.get(key)) |index| &table.items[index] else null;
        }
    };
}

pub const TableConfigManager = struct {
    arena: ArenaAllocator,
    sprite_common_table: SpriteCommonTable,
    trainer_common_table_config: TrainerCommonTableConfig,
    player_avatar_table_config: PlayerAvatarTableConfig,
    teleport_table: TeleportTable,

    pub fn loadAll(gpa: Allocator, config_dir: std.fs.Dir) !@This() {
        var self: @This() = undefined;
        self.arena = ArenaAllocator.init(gpa);
        errdefer self.arena.deinit();

        const arena = self.arena.allocator();

        const json_options: std.json.ParseOptions = .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        };

        inline for (std.meta.fields(@This())) |field| {
            if (field.type == ArenaAllocator) continue;

            const content = try config_dir.readFileAlloc(gpa, comptime field.type.filename, 1024 * 1024);
            defer gpa.free(content);

            if (@hasDecl(field.type, "loadFromJson")) {
                @field(self, field.name) = try field.type.loadFromJson(arena, content, json_options);
            } else {
                @field(self, field.name) = try std.json.parseFromSliceLeaky(field.type, arena, content, json_options);
            }
        }

        return self;
    }

    pub fn deinit(table_mgr: *@This()) void {
        table_mgr.arena.deinit();
    }
};
