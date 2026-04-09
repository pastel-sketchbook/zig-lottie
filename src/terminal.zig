const std = @import("std");
const lottie = @import("zig-lottie");
const rasterizer = @import("rasterizer");
const kitty = @import("kitty");
const Allocator = std.mem.Allocator;
const posix = std.posix;

// ---------------------------------------------------------------
// Terminal Size Detection
// ---------------------------------------------------------------

/// Terminal pixel dimensions as reported by the terminal emulator.
pub const TerminalPixelSize = struct {
    width: u32,
    height: u32,
};

/// Query the terminal's pixel dimensions via TIOCGWINSZ ioctl.
/// Returns null if the ioctl fails (e.g. stdout is piped, not a tty,
/// or the terminal does not report pixel dimensions).
pub fn getTerminalPixelSize(fd: posix.fd_t) ?TerminalPixelSize {
    var wsz: posix.winsize = .{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    const err = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (posix.errno(err) != .SUCCESS) return null;

    // Some terminals report 0 for pixel dimensions even on success
    if (wsz.xpixel == 0 or wsz.ypixel == 0) return null;

    return .{
        .width = @as(u32, wsz.xpixel),
        .height = @as(u32, wsz.ypixel),
    };
}

/// Determine the default output width for rendering.
/// Priority: 1) explicit config width, 2) terminal pixel width, 3) fallback cap of 800.
fn defaultOutputWidth(anim_width: u32, config_width: ?u32) u32 {
    if (config_width) |w| return w;

    // Try to detect terminal pixel width from stdout
    if (getTerminalPixelSize(std.posix.STDOUT_FILENO)) |term_size| {
        return @min(anim_width, term_size.width);
    }

    return @min(anim_width, 800);
}

// ---------------------------------------------------------------
// Terminal Lottie Renderer
// ---------------------------------------------------------------

/// Configuration for terminal rendering.
pub const RenderConfig = struct {
    /// Output width in pixels (default: animation width, capped at terminal width or 800).
    width: ?u32 = null,
    /// Output height in pixels (default: proportional to width).
    height: ?u32 = null,
    /// Background color [r, g, b, a].
    background: rasterizer.Pixel = .{ 0, 0, 0, 0 },
    /// Number of loops (0 = infinite).
    loops: u32 = 1,
    /// Render a single frame (null = animate).
    frame: ?f64 = null,
};

/// Render a Lottie animation to the terminal using Kitty graphics protocol.
/// This is the main entry point for the `render` subcommand.
pub fn render(
    allocator: Allocator,
    anim: *const lottie.Animation,
    config: RenderConfig,
    writer: anytype,
) !void {
    // Determine output dimensions
    const out_w = defaultOutputWidth(anim.width, config.width);
    const out_h = config.height orelse blk: {
        const aspect = @as(f64, @floatFromInt(anim.height)) / @as(f64, @floatFromInt(anim.width));
        break :blk @as(u32, @intFromFloat(@as(f64, @floatFromInt(out_w)) * aspect));
    };

    // Scale factor from animation space to output space
    const scale_x = @as(f64, @floatFromInt(out_w)) / @as(f64, @floatFromInt(anim.width));
    const scale_y = @as(f64, @floatFromInt(out_h)) / @as(f64, @floatFromInt(anim.height));

    // Estimate terminal rows the image will occupy (~1 row per 20 pixels is typical)
    // This is approximate; actual depends on terminal cell size.
    const approx_rows: u32 = @max(1, out_h / 20);

    if (config.frame) |frame_num| {
        // Single frame mode
        var buf = try rasterizer.PixelBuffer.init(allocator, out_w, out_h, config.background);
        defer buf.deinit();

        const frame = try lottie.compileFrame(allocator, anim, frame_num);
        defer frame.deinit();

        const scale_mat = rasterizer.Matrix.scale(scale_x, scale_y);
        rasterizer.renderFrame(&buf, &frame, scale_mat);
        try kitty.encodeImage(writer, &buf);
        try writer.writeAll("\n");
        return;
    }

    // Animation mode
    const frame_start: i64 = @intFromFloat(@floor(anim.in_point));
    const frame_end: i64 = @intFromFloat(@ceil(anim.out_point));
    const total_frames: usize = if (frame_end > frame_start) @intCast(frame_end - frame_start) else 0;
    if (total_frames == 0) return;

    const frame_duration_ns: u64 = @intFromFloat(1_000_000_000.0 / anim.frame_rate);

    var buf = try rasterizer.PixelBuffer.init(allocator, out_w, out_h, config.background);
    defer buf.deinit();

    const scale_mat = rasterizer.Matrix.scale(scale_x, scale_y);

    try kitty.hideCursor(writer);
    defer kitty.showCursor(writer) catch {};

    var loops_done: u32 = 0;
    while (config.loops == 0 or loops_done < config.loops) : (loops_done += 1) {
        for (0..total_frames) |fi| {
            const frame_time: f64 = @floatFromInt(frame_start + @as(i64, @intCast(fi)));
            var timer = try std.time.Timer.start();

            buf.clear(config.background);

            const frame = try lottie.compileFrame(allocator, anim, frame_time);
            defer frame.deinit();

            rasterizer.renderFrame(&buf, &frame, scale_mat);

            // Move cursor back to overwrite the previous frame
            if (fi > 0 or loops_done > 0) {
                try kitty.cursorHome(writer);
                try kitty.cursorUp(writer, approx_rows);
            }

            try kitty.encodeImage(writer, &buf);
            try writer.writeAll("\n");

            // Sleep for remaining frame time
            const elapsed_ns = timer.read();
            if (elapsed_ns < frame_duration_ns) {
                std.Thread.sleep(frame_duration_ns - elapsed_ns);
            }
        }
    }
}

/// Render a single static frame and return the pixel buffer (for testing).
pub fn renderSingleFrame(
    allocator: Allocator,
    anim: *const lottie.Animation,
    frame_num: f64,
    width: u32,
    height: u32,
    background: rasterizer.Pixel,
) !rasterizer.PixelBuffer {
    var buf = try rasterizer.PixelBuffer.init(allocator, width, height, background);
    errdefer buf.deinit();

    const frame = try lottie.compileFrame(allocator, anim, frame_num);
    defer frame.deinit();

    const scale_x = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(anim.width));
    const scale_y = @as(f64, @floatFromInt(height)) / @as(f64, @floatFromInt(anim.height));
    const scale_mat = rasterizer.Matrix.scale(scale_x, scale_y);

    rasterizer.renderFrame(&buf, &frame, scale_mat);
    return buf;
}

// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

const testing = std.testing;

test "renderSingleFrame: red rect on black" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"gr","it":[
        \\      {"ty":"rc","s":{"a":0,"k":[80,80]},"p":{"a":0,"k":[50,50]}},
        \\      {"ty":"fl","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}},
        \\      {"ty":"tr","a":{"a":0,"k":[0,0]},"p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
        \\    ]}
        \\  ]}
        \\]}
    ;
    const anim = try lottie.parse(testing.allocator, json);
    defer anim.deinit();

    var buf = try renderSingleFrame(testing.allocator, &anim, 0, 100, 100, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // Center of the rect should be red
    const center = buf.getPixel(50, 50).?;
    try testing.expectEqual(@as(u8, 255), center[0]);
    try testing.expectEqual(@as(u8, 0), center[1]);
    try testing.expectEqual(@as(u8, 0), center[2]);

    // Corner should be black background
    const corner = buf.getPixel(0, 0).?;
    try testing.expectEqual(@as(u8, 0), corner[0]);
}

test "renderSingleFrame: ellipse on white" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"gr","it":[
        \\      {"ty":"el","s":{"a":0,"k":[60,60]},"p":{"a":0,"k":[50,50]}},
        \\      {"ty":"fl","c":{"a":0,"k":[0,0,1,1]},"o":{"a":0,"k":100}},
        \\      {"ty":"tr","a":{"a":0,"k":[0,0]},"p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
        \\    ]}
        \\  ]}
        \\]}
    ;
    const anim = try lottie.parse(testing.allocator, json);
    defer anim.deinit();

    var buf = try renderSingleFrame(testing.allocator, &anim, 0, 100, 100, .{ 255, 255, 255, 255 });
    defer buf.deinit();

    // Center of ellipse should be blue
    const center = buf.getPixel(50, 50).?;
    try testing.expectEqual(@as(u8, 0), center[0]);
    try testing.expectEqual(@as(u8, 0), center[1]);
    try testing.expectEqual(@as(u8, 255), center[2]);
}

test "renderSingleFrame: invisible layer produces no shapes" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":30,"op":60,"shapes":[
        \\    {"ty":"gr","it":[
        \\      {"ty":"rc","s":{"a":0,"k":[100,100]},"p":{"a":0,"k":[50,50]}},
        \\      {"ty":"fl","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}},
        \\      {"ty":"tr","a":{"a":0,"k":[0,0]},"p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
        \\    ]}
        \\  ]}
        \\]}
    ;
    const anim = try lottie.parse(testing.allocator, json);
    defer anim.deinit();

    // At frame 0, layer is not visible (starts at frame 30)
    var buf = try renderSingleFrame(testing.allocator, &anim, 0, 100, 100, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // Everything should be black
    const center = buf.getPixel(50, 50).?;
    try testing.expectEqual(@as(u8, 0), center[0]);
}

test "defaultOutputWidth: explicit config takes priority" {
    try testing.expectEqual(@as(u32, 400), defaultOutputWidth(1920, 400));
}

test "defaultOutputWidth: falls back to capped anim width without terminal" {
    // When running in test, stdout is not a terminal — so getTerminalPixelSize
    // should return null and we fall through to the 800px cap.
    try testing.expectEqual(@as(u32, 800), defaultOutputWidth(1920, null));
}

test "defaultOutputWidth: small anim uses anim width as fallback" {
    // Animation smaller than 800px should use its own width
    try testing.expectEqual(@as(u32, 320), defaultOutputWidth(320, null));
}

test "getTerminalPixelSize: returns null for invalid fd" {
    // fd -1 is invalid, ioctl should fail
    const result = getTerminalPixelSize(-1);
    try testing.expect(result == null);
}
