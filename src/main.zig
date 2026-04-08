const std = @import("std");
const lottie = @import("zig-lottie");

pub fn main() !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    var args = std.process.args();
    _ = args.skip(); // skip executable name

    const subcommand = args.next() orelse {
        try printUsage(stdout);
        return;
    };

    if (std.mem.eql(u8, subcommand, "version")) {
        try stdout.print("zig-lottie {s}\n", .{lottie.version});
    } else if (std.mem.eql(u8, subcommand, "inspect")) {
        const path = args.next() orelse {
            try stderr.print("error: inspect requires a file path\n", .{});
            stderr.flush() catch {};
            std.process.exit(1);
        };
        try inspectFile(path, stdout, stderr);
    } else if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage(stdout);
    } else {
        try stderr.print("error: unknown command '{s}'\n", .{subcommand});
        try printUsage(stderr);
        stderr.flush() catch {};
        std.process.exit(1);
    }
}

fn inspectFile(path: []const u8, writer: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    const allocator = std.heap.page_allocator;

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try stderr.print("error: cannot open '{s}': {}\n", .{ path, err });
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 64 * 1024 * 1024) catch |err| {
        try stderr.print("error: cannot read '{s}': {}\n", .{ path, err });
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer allocator.free(contents);

    const anim = lottie.parse(allocator, contents) catch |err| {
        try stderr.print("error: failed to parse '{s}': {}\n", .{ path, err });
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer anim.deinit();

    try writer.print("File:       {s}\n", .{path});
    try writer.print("Version:    {s}\n", .{anim.version_str});
    try writer.print("Frame rate: {d}\n", .{anim.frame_rate});
    try writer.print("Duration:   {d:.2}s\n", .{anim.duration()});
    try writer.print("Frames:     {d} - {d}\n", .{ anim.in_point, anim.out_point });
    try writer.print("Size:       {d}x{d}\n", .{ anim.width, anim.height });
    if (anim.name) |name| {
        try writer.print("Name:       {s}\n", .{name});
    }
    try writer.print("Layers:     {d}\n", .{anim.layers.len});

    for (anim.layers, 0..) |layer, i| {
        try writer.print("  [{d}] type={d}", .{ i, @intFromEnum(layer.ty) });
        if (layer.name) |name| {
            try writer.print(" name=\"{s}\"", .{name});
        }
        if (layer.index) |ind| {
            try writer.print(" index={d}", .{ind});
        }
        if (layer.transform != null) {
            try writer.print(" +transform", .{});
        }
        if (layer.shapes.len > 0) {
            try writer.print(" shapes={d}", .{layer.shapes.len});
        }
        try writer.print("\n", .{});

        // Print shapes tree
        try printShapes(writer, layer.shapes, 2);
    }
}

fn printShapes(writer: *std.Io.Writer, shapes: []const lottie.Shape, depth: usize) !void {
    for (shapes) |shape| {
        // Indent
        for (0..depth) |_| try writer.print("  ", .{});
        try writer.print("- {s}", .{shapeTypeName(shape.ty)});
        if (shape.name) |name| {
            try writer.print(" \"{s}\"", .{name});
        }
        if (shape.items.len > 0) {
            try writer.print(" ({d} items)", .{shape.items.len});
        }
        try writer.print("\n", .{});

        // Recurse into group items
        if (shape.items.len > 0) {
            try printShapes(writer, shape.items, depth + 1);
        }
    }
}

fn shapeTypeName(ty: lottie.ShapeType) []const u8 {
    return switch (ty) {
        .group => "group",
        .rectangle => "rectangle",
        .ellipse => "ellipse",
        .path => "path",
        .fill => "fill",
        .stroke => "stroke",
        .transform => "transform",
        .gradient_fill => "gradient-fill",
        .gradient_stroke => "gradient-stroke",
        .merge => "merge",
        .trim => "trim",
        .round_corners => "round-corners",
        .repeater => "repeater",
        .star => "star",
        .unknown => "unknown",
    };
}

fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\Usage: zig-lottie <command> [args]
        \\
        \\Commands:
        \\  version            Print version
        \\  inspect <file>     Parse and display Lottie animation info
        \\  help               Show this help
        \\
    , .{});
}

test "printUsage does not error" {
    // Verify printUsage runs without crashing by writing to stderr.
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    try printUsage(&stderr_writer.interface);
}
