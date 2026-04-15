const std = @import("std");
const Allocator = std.mem.Allocator;
const rasterizer = @import("rasterizer");

// ---------------------------------------------------------------
// Kitty Graphics Protocol
// ---------------------------------------------------------------
//
// The Kitty graphics protocol sends images inline via escape sequences:
//   ESC_G<key>=<value>[,<key>=<value>...];[payload]ST
//
// Where ESC_G = "\x1b_G" and ST = "\x1b\\"
//
// Key parameters for our use:
//   f=32   — RGBA pixel format (32 bits per pixel)
//   s=W    — image width in pixels
//   v=H    — image height in pixels
//   a=T    — action: transmit and display
//   t=d    — transmission: direct (data in payload)
//   m=0/1  — more data follows (chunked transfer)
//   q=2    — suppress response from terminal
//
// For animation we also use:
//   a=p    — action: put (display at cursor, for replacement)
//
// Payload is base64-encoded RGBA data.
// Chunks must be <= 4096 bytes of base64 per escape sequence.

const ESC_G = "\x1b_G";
const ST = "\x1b\\";
const BASE64_CHUNK_SIZE = 4096;

/// Encode RGBA pixel data to Kitty graphics protocol escape sequences.
/// Streams base64 encoding in chunks without heap allocation.
pub fn encodeImage(writer: anytype, buf: *const rasterizer.PixelBuffer) !void {
    try encodeImageChunked(writer, buf, null);
}

/// Streaming chunked encoder shared by encodeImage and encodeImageReplace.
/// Encodes raw RGBA data to base64 in fixed-size chunks, writing each chunk
/// as a separate Kitty escape sequence. No heap allocation needed.
fn encodeImageChunked(writer: anytype, buf: *const rasterizer.PixelBuffer, image_id: ?u32) !void {
    const data = buf.data;
    const total_b64_len = ((data.len + 2) / 3) * 4;

    // Number of raw bytes that produce exactly BASE64_CHUNK_SIZE base64 chars
    const raw_per_chunk: usize = (BASE64_CHUNK_SIZE / 4) * 3; // 3072

    var raw_offset: usize = 0;
    var b64_written: usize = 0;
    var first = true;
    var b64_buf: [BASE64_CHUNK_SIZE + 4]u8 = undefined; // small stack buffer for one chunk

    while (b64_written < total_b64_len) {
        const raw_end = @min(raw_offset + raw_per_chunk, data.len);
        const chunk = data[raw_offset..raw_end];

        const encoded = std.base64.standard.Encoder.encode(&b64_buf, chunk);
        const is_last = raw_end == data.len;

        try writer.writeAll(ESC_G);
        if (first) {
            if (image_id) |id| {
                try writer.print("a=T,f=32,s={d},v={d},i={d},p=1,q=2,m={d};", .{
                    buf.width,
                    buf.height,
                    id,
                    @as(u8, if (is_last) 0 else 1),
                });
            } else {
                try writer.print("a=T,f=32,s={d},v={d},q=2,m={d};", .{
                    buf.width,
                    buf.height,
                    @as(u8, if (is_last) 0 else 1),
                });
            }
            first = false;
        } else {
            try writer.print("m={d};", .{@as(u8, if (is_last) 0 else 1)});
        }
        try writer.writeAll(encoded);
        try writer.writeAll(ST);

        raw_offset = raw_end;
        b64_written += encoded.len;
    }
}

/// Encode a replacement image at the cursor position (for animation).
/// Uses placement to allow clearing/replacing.
pub fn encodeImageReplace(writer: anytype, buf: *const rasterizer.PixelBuffer, image_id: u32) !void {
    try encodeImageChunked(writer, buf, image_id);
}

/// Delete an image by ID.
pub fn deleteImage(writer: anytype, image_id: u32) !void {
    try writer.writeAll(ESC_G);
    try writer.print("a=d,d=I,i={d},q=2;", .{image_id});
    try writer.writeAll(ST);
}

/// Move cursor up N lines (to reposition for animation frame replacement).
pub fn cursorUp(writer: anytype, lines: u32) !void {
    if (lines > 0) {
        try writer.print("\x1b[{d}A", .{lines});
    }
}

/// Move cursor to start of line.
pub fn cursorHome(writer: anytype) !void {
    try writer.writeAll("\r");
}

/// Hide cursor.
pub fn hideCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25l");
}

/// Show cursor.
pub fn showCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25h");
}

// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

const testing = std.testing;

test "encodeImage: small image produces valid escape sequence" {
    // Create a tiny 2x2 RGBA buffer
    var buf = try rasterizer.PixelBuffer.init(testing.allocator, 2, 2, .{ 255, 0, 0, 255 });
    defer buf.deinit();

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try encodeImage(&aw.writer, &buf);
    const result = aw.writer.buffered();

    // Should start with ESC_G and end with ST
    try testing.expect(std.mem.startsWith(u8, result, ESC_G));
    try testing.expect(std.mem.endsWith(u8, result, ST));

    // Should contain the format/size parameters
    try testing.expect(std.mem.indexOf(u8, result, "f=32") != null);
    try testing.expect(std.mem.indexOf(u8, result, "s=2") != null);
    try testing.expect(std.mem.indexOf(u8, result, "v=2") != null);
}

test "encodeImage: parameters include action and quiet" {
    var buf = try rasterizer.PixelBuffer.init(testing.allocator, 1, 1, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try encodeImage(&aw.writer, &buf);
    const result = aw.writer.buffered();

    try testing.expect(std.mem.indexOf(u8, result, "a=T") != null);
    try testing.expect(std.mem.indexOf(u8, result, "q=2") != null);
}

test "encodeImageReplace: includes image ID" {
    var buf = try rasterizer.PixelBuffer.init(testing.allocator, 1, 1, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try encodeImageReplace(&aw.writer, &buf, 42);
    const result = aw.writer.buffered();

    try testing.expect(std.mem.indexOf(u8, result, "i=42") != null);
}

test "deleteImage: produces valid delete sequence" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try deleteImage(&aw.writer, 7);
    const result = aw.writer.buffered();

    try testing.expect(std.mem.startsWith(u8, result, ESC_G));
    try testing.expect(std.mem.indexOf(u8, result, "a=d") != null);
    try testing.expect(std.mem.indexOf(u8, result, "i=7") != null);
}

test "cursorUp: emits ANSI escape" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try cursorUp(&aw.writer, 5);
    try testing.expectEqualStrings("\x1b[5A", aw.writer.buffered());
}

test "hideCursor and showCursor" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try hideCursor(&aw.writer);
    try testing.expectEqualStrings("\x1b[?25l", aw.writer.buffered());
}

test "showCursor" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();

    try showCursor(&aw.writer);
    try testing.expectEqualStrings("\x1b[?25h", aw.writer.buffered());
}
