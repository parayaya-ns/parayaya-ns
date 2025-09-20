const std = @import("std");
const builtin = @import("builtin");
const protobuf = @import("protobuf_abc");

const main_proto_file = "proto/cs_proto/ABC.proto";
const protoc_output_dir = "proto/src/pb";
const proto_module_name = "proto";
const common_module_name = "common";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opts = .{ .target = target, .optimize = optimize };

    const protobuf_dep = b.dependency("protobuf_abc", opts);
    const protoc_step = createProtocStep(b, protobuf_dep);

    const proto = b.createModule(.{
        .root_source_file = b.path("proto/src/root.zig"),
        .imports = &.{.{ .name = "protobuf", .module = protobuf_dep.module("protobuf") }},
        .target = target,
        .optimize = optimize,
    });

    const common = b.createModule(.{
        .root_source_file = b.path("common/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dispatch_server = createDispatchExecutable(b, proto, common, target, optimize);
    const game_server = createGameServerExecutable(b, proto, common, target, optimize);

    if (protoc_step) |step| {
        dispatch_server.step.dependOn(step);
        game_server.step.dependOn(step);
    }

    b.step(
        "run-parayaya-dispatch",
        "Run the dispatch-server",
    ).dependOn(&b.addRunArtifact(dispatch_server).step);

    b.step(
        "run-parayaya-gameserver",
        "Run the game-server",
    ).dependOn(&b.addRunArtifact(game_server).step);

    const dispatch_artifact = b.addInstallArtifact(dispatch_server, .{});
    const game_server_artifact = b.addInstallArtifact(game_server, .{});

    b.step(
        "build-parayaya-dispatch",
        "Compile the dispatch-server",
    ).dependOn(&dispatch_artifact.step);

    b.step(
        "build-parayaya-gameserver",
        "Compile the game-server",
    ).dependOn(&game_server_artifact.step);

    const build_all = b.step(
        "build-all-servers",
        "Compile dispatch-server and game-server",
    );

    build_all.dependOn(&dispatch_artifact.step);
    build_all.dependOn(&game_server_artifact.step);
}

fn createDispatchExecutable(
    b: *std.Build,
    proto: *std.Build.Module,
    common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const assets: []const []const u8 = &.{
        "client_public_key.der",
        "server_private_key.der",
        "dispatch_config.default.zon",
    };

    const module = b.createModule(.{
        .root_source_file = b.path("dispatch-server/src/main.zig"),
        .imports = &.{
            .{ .name = proto_module_name, .module = proto },
            .{ .name = common_module_name, .module = common },
        },
        .target = target,
        .optimize = optimize,
    });

    inline for (assets) |filename| {
        module.addAnonymousImport(
            filename,
            .{ .root_source_file = b.path("dispatch-server/" ++ filename) },
        );
    }

    addAutopatchAssets(b, module);

    return b.addExecutable(.{
        .name = "parayaya-dispatch-server",
        .root_module = module,
    });
}

fn createGameServerExecutable(
    b: *std.Build,
    proto: *std.Build.Module,
    common: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("game-server/src/main.zig"),
        .imports = &.{
            .{ .name = proto_module_name, .module = proto },
            .{ .name = common_module_name, .module = common },
        },
        .target = target,
        .optimize = optimize,
    });

    return b.addExecutable(.{
        .name = "parayaya-game-server",
        .root_module = module,
    });
}

fn addAutopatchAssets(b: *std.Build, to_module: *std.Build.Module) void {
    const assets: []const []const u8 = &.{
        "ini/v0.3_live/820659_5356a584dd/DefaultSettings.bin",
        "ini/v0.3_live/820659_5356a584dd/DefaultDeviceProfile.bin",
        "ini/v0.3_live/820659_5356a584dd/Windows/DefaultSettings.bin",
        "ini/v0.3_live/820659_5356a584dd/Windows/DefaultDeviceProfile.bin",
        "ifix/v0.3_live/1188647018_836485/Windows/Patch/ifix.manifest",
        "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.Adventure.dll.patch",
        "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.Chess.dll.patch",
        "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.Common.dll.patch",
        "ifix/v0.3_live/1188647018_836485/Windows/Patch/ABC.TechArt.dll.patch",
        "design_data/v0.3_live/847131_e347a33b7f/Block/ConfigDownloadManifest.bin",
        "audio/v0.3_live/820661_d420f801f3/Windows/DownloadManifests/AudioDownloadManifest.bin",
        "video/v0.3_live/821844_90bb61786e/Windows/videoconfig.bin",
        "resource/v0.3_live/847921_ab1b0dc1e2/Windows/Block/ArchiveVerifyConfig_0_3.bin",
        "resource/v0.3_live/847921_ab1b0dc1e2/Windows/Patch/ContentPatchConfig.bin",
    };

    inline for (assets) |filename| {
        to_module.addAnonymousImport(
            filename,
            .{ .root_source_file = b.path("assets/autopatch/" ++ filename) },
        );
    }
}

fn createProtocStep(b: *std.Build, pb_dep: *std.Build.Dependency) ?*std.Build.Step {
    std.fs.cwd().access(main_proto_file, .{}) catch return null;

    const t = resolveHostTarget();
    const protoc_step = protobuf.RunProtocStep.create(b, pb_dep.builder, t, .{
        .destination_directory = b.path(protoc_output_dir),
        .source_files = &.{main_proto_file},
        .include_directories = &.{},
    });

    return &protoc_step.step;
}

fn resolveHostTarget() std.Build.ResolvedTarget {
    return .{
        .query = .fromTarget(&builtin.target),
        .result = builtin.target,
    };
}
