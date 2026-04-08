const std = @import("std");
const lottie = @import("zig-lottie");
const terminal = @import("terminal");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

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
        try inspectFile(allocator, path, stdout, stderr);
    } else if (std.mem.eql(u8, subcommand, "validate")) {
        const path = args.next() orelse {
            try stderr.print("error: validate requires a file path\n", .{});
            stderr.flush() catch {};
            std.process.exit(1);
        };
        try validateFile(allocator, path, stdout, stderr);
    } else if (std.mem.eql(u8, subcommand, "render")) {
        const path = args.next() orelse {
            try stderr.print("error: render requires a file path\n", .{});
            stderr.flush() catch {};
            std.process.exit(1);
        };
        try renderFile(allocator, path, &args, stdout, stderr);
    } else if (std.mem.eql(u8, subcommand, "help")) {
        try printUsage(stdout);
    } else {
        try stderr.print("error: unknown command '{s}'\n", .{subcommand});
        try printUsage(stderr);
        stderr.flush() catch {};
        std.process.exit(1);
    }
}

fn inspectFile(allocator: std.mem.Allocator, path: []const u8, writer: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    const anim = loadAndParse(allocator, path, stderr);
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

    // Layer type counts
    var layer_type_counts = [_]usize{0} ** 16;
    for (anim.layers) |layer| {
        const idx = @intFromEnum(layer.ty);
        if (idx < 16) layer_type_counts[idx] += 1;
    }
    try writer.print("            ", .{});
    var first_lt = true;
    const lt_names = [_][]const u8{
        "precomp",    "solid",             "image",     "null",  "shape",             "text",
        "audio",      "video_placeholder", "image_seq", "video", "image_placeholder", "guide",
        "adjustment", "camera",            "light",     "data",
    };
    for (layer_type_counts, 0..) |count, ti| {
        if (count == 0) continue;
        if (!first_lt) try writer.print(", ", .{});
        first_lt = false;
        try writer.print("{d} {s}", .{ count, lt_names[ti] });
    }
    try writer.print("\n", .{});

    // Shape type and keyframe summary
    var shape_counts = [_]usize{0} ** 15;
    var total_keyframes: usize = 0;
    for (anim.layers) |layer| {
        countShapeTypes(layer.shapes, &shape_counts);
        total_keyframes += countKeyframes(layer.transform);
        for (layer.shapes) |shape| {
            total_keyframes += countShapeKeyframes(shape);
        }
    }

    // Print shape summary if any shapes exist
    var total_shapes: usize = 0;
    for (shape_counts) |c| total_shapes += c;
    if (total_shapes > 0) {
        try writer.print("Shapes:     {d}\n", .{total_shapes});
        try writer.print("            ", .{});
        var first_st = true;
        const st_names = [_][]const u8{
            "group",     "rect",      "ellipse",     "path",  "fill", "stroke",
            "transform", "grad-fill", "grad-stroke", "merge", "trim", "round-corners",
            "repeater",  "star",      "unknown",
        };
        for (shape_counts, 0..) |count, si| {
            if (count == 0) continue;
            if (!first_st) try writer.print(", ", .{});
            first_st = false;
            try writer.print("{d} {s}", .{ count, st_names[si] });
        }
        try writer.print("\n", .{});
    }

    if (total_keyframes > 0) {
        try writer.print("Keyframes:  {d}\n", .{total_keyframes});
    }

    // Detailed layer listing
    try writer.print("\n", .{});
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

    // Run validation and display any issues
    const issues = lottie.validate(allocator, &anim) catch |err| {
        try stderr.print("warning: validation failed: {}\n", .{err});
        return;
    };
    defer {
        for (issues) |issue| allocator.free(issue.message);
        allocator.free(issues);
    }

    if (issues.len > 0) {
        try writer.print("\nValidation:\n", .{});
        try printIssues(writer, issues);
    }
}

fn validateFile(allocator: std.mem.Allocator, path: []const u8, writer: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    const anim = loadAndParse(allocator, path, stderr);
    defer anim.deinit();

    const issues = lottie.validate(allocator, &anim) catch |err| {
        try stderr.print("error: validation failed: {}\n", .{err});
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer {
        for (issues) |issue| allocator.free(issue.message);
        allocator.free(issues);
    }

    if (issues.len == 0) {
        try writer.print("{s}: valid\n", .{path});
        return;
    }

    try writer.print("{s}:\n", .{path});
    try printIssues(writer, issues);

    // Count errors
    var errors: usize = 0;
    for (issues) |issue| {
        if (issue.severity == .@"error") errors += 1;
    }
    const warnings = issues.len - errors;

    try writer.print("\n{d} error(s), {d} warning(s)\n", .{ errors, warnings });

    if (errors > 0) {
        writer.flush() catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    }
}

fn loadAndParse(allocator: std.mem.Allocator, path: []const u8, stderr: *std.Io.Writer) lottie.Animation {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        stderr.print("error: cannot open '{s}': {}\n", .{ path, err }) catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 64 * 1024 * 1024) catch |err| {
        stderr.print("error: cannot read '{s}': {}\n", .{ path, err }) catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer allocator.free(contents);

    return lottie.parse(allocator, contents) catch |err| {
        stderr.print("error: failed to parse '{s}': {}\n", .{ path, err }) catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    };
}

fn renderFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    args: *std.process.ArgIterator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    var config = terminal.RenderConfig{};

    // Parse optional flags
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--width")) {
            const val = args.next() orelse {
                try stderr.print("error: --width requires a value\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
            config.width = std.fmt.parseInt(u32, val, 10) catch {
                try stderr.print("error: invalid width '{s}'\n", .{val});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--height")) {
            const val = args.next() orelse {
                try stderr.print("error: --height requires a value\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
            config.height = std.fmt.parseInt(u32, val, 10) catch {
                try stderr.print("error: invalid height '{s}'\n", .{val});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--frame")) {
            const val = args.next() orelse {
                try stderr.print("error: --frame requires a value\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
            config.frame = std.fmt.parseFloat(f64, val) catch {
                try stderr.print("error: invalid frame '{s}'\n", .{val});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--loops")) {
            const val = args.next() orelse {
                try stderr.print("error: --loops requires a value\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
            config.loops = std.fmt.parseInt(u32, val, 10) catch {
                try stderr.print("error: invalid loops '{s}'\n", .{val});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--bg")) {
            const val = args.next() orelse {
                try stderr.print("error: --bg requires a hex color (RRGGBB)\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
            config.background = parseHexColor(val) orelse {
                try stderr.print("error: invalid color '{s}' (expected RRGGBB)\n", .{val});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else {
            try stderr.print("error: unknown option '{s}'\n", .{arg});
            stderr.flush() catch {};
            std.process.exit(1);
        }
    }

    const anim = loadAndParse(allocator, path, stderr);
    defer anim.deinit();

    // Flush stdout buffer before terminal.render takes over raw output
    stdout.flush() catch {};

    terminal.render(allocator, &anim, config, stdout) catch |err| {
        try stderr.print("error: render failed: {}\n", .{err});
        stderr.flush() catch {};
        std.process.exit(1);
    };
}

fn parseHexColor(hex: []const u8) ?@import("rasterizer").Pixel {
    if (hex.len != 6) return null;
    const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return null;
    const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return null;
    const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return null;
    return .{ r, g, b, 255 };
}

fn printIssues(writer: *std.Io.Writer, issues: []const lottie.ValidationIssue) !void {
    for (issues) |issue| {
        const prefix: []const u8 = switch (issue.severity) {
            .@"error" => "  ERROR: ",
            .warning => "  WARN:  ",
        };
        try writer.print("{s}{s}\n", .{ prefix, issue.message });
    }
}

fn countShapeTypes(shapes: []const lottie.Shape, counts: *[15]usize) void {
    for (shapes) |shape| {
        const idx = @intFromEnum(shape.ty);
        if (idx < 15) counts[idx] += 1;
        countShapeTypes(shape.items, counts);
    }
}

fn countKeyframes(transform: ?lottie.Transform) usize {
    const tr = transform orelse return 0;
    var n: usize = 0;
    n += countAnimatedMultiKfs(tr.anchor);
    n += countAnimatedMultiKfs(tr.position);
    n += countAnimatedMultiKfs(tr.scale);
    n += countAnimatedValueKfs(tr.rotation);
    n += countAnimatedValueKfs(tr.opacity);
    return n;
}

fn countAnimatedValueKfs(av: ?lottie.AnimatedValue) usize {
    const v = av orelse return 0;
    return switch (v) {
        .keyframed => |kfs| kfs.len,
        .static => 0,
    };
}

fn countAnimatedMultiKfs(am: ?lottie.AnimatedMulti) usize {
    const v = am orelse return 0;
    return switch (v) {
        .keyframed => |kfs| kfs.len,
        .static => 0,
    };
}

fn countShapeKeyframes(shape: lottie.Shape) usize {
    var n: usize = 0;
    n += countAnimatedMultiKfs(shape.size);
    n += countAnimatedMultiKfs(shape.position);
    n += countAnimatedValueKfs(shape.roundness);
    n += countAnimatedMultiKfs(shape.color);
    n += countAnimatedValueKfs(shape.opacity);
    n += countAnimatedValueKfs(shape.stroke_width);
    n += countKeyframes(shape.transform);
    for (shape.items) |item| {
        n += countShapeKeyframes(item);
    }
    return n;
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
        \\  version              Print version
        \\  inspect <file>       Parse and display Lottie animation info
        \\  validate <file>      Validate a Lottie file for semantic correctness
        \\  render <file> [opts] Render animation in terminal (Kitty graphics)
        \\  help                 Show this help
        \\
        \\Render options:
        \\  --width <N>          Output width in pixels (default: anim width, max 800)
        \\  --height <N>         Output height in pixels (default: proportional)
        \\  --frame <N>          Render a single frame number
        \\  --loops <N>          Number of loops (0 = infinite, default: 1)
        \\  --bg <RRGGBB>        Background color in hex (default: transparent)
        \\
    , .{});
}

test "printUsage does not error" {
    // Verify printUsage runs without crashing by writing to stderr.
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    try printUsage(&stderr_writer.interface);
}
