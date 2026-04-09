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
// Base64 encoding
// ---------------------------------------------------------------

const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Base64 encode a byte slice. Caller owns the returned slice.
pub fn base64Encode(data: []const u8) ![]u8 {
    const out_len = ((data.len + 2) / 3) * 4;
    const out = try std.heap.page_allocator.alloc(u8, out_len);

    var i: usize = 0;
    var o: usize = 0;
    while (i + 3 <= data.len) : ({
        i += 3;
        o += 4;
    }) {
        const b0: u32 = data[i];
        const b1: u32 = data[i + 1];
        const b2: u32 = data[i + 2];
        const val = (b0 << 16) | (b1 << 8) | b2;
        out[o] = base64_chars[(val >> 18) & 0x3f];
        out[o + 1] = base64_chars[(val >> 12) & 0x3f];
        out[o + 2] = base64_chars[(val >> 6) & 0x3f];
        out[o + 3] = base64_chars[val & 0x3f];
    }

    const remaining = data.len - i;
    if (remaining == 1) {
        const b0: u32 = data[i];
        const val = b0 << 16;
        out[o] = base64_chars[(val >> 18) & 0x3f];
        out[o + 1] = base64_chars[(val >> 12) & 0x3f];
        out[o + 2] = '=';
        out[o + 3] = '=';
    } else if (remaining == 2) {
        const b0: u32 = data[i];
        const b1: u32 = data[i + 1];
        const val = (b0 << 16) | (b1 << 8);
        out[o] = base64_chars[(val >> 18) & 0x3f];
        out[o + 1] = base64_chars[(val >> 12) & 0x3f];
        out[o + 2] = base64_chars[(val >> 6) & 0x3f];
        out[o + 3] = '=';
    }

    return out;
}

// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

const testing = std.testing;

test "base64Encode: empty" {
    const result = try base64Encode("");
    defer std.heap.page_allocator.free(result);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "base64Encode: standard test vectors" {
    // RFC 4648 test vectors
    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "f", .expected = "Zg==" },
        .{ .input = "fo", .expected = "Zm8=" },
        .{ .input = "foo", .expected = "Zm9v" },
        .{ .input = "foob", .expected = "Zm9vYg==" },
        .{ .input = "fooba", .expected = "Zm9vYmE=" },
        .{ .input = "foobar", .expected = "Zm9vYmFy" },
    };
    for (cases) |tc| {
        const result = try base64Encode(tc.input);
        defer std.heap.page_allocator.free(result);
        try testing.expectEqualStrings(tc.expected, result);
    }
}

test "encodeImage: small image produces valid escape sequence" {
    // Create a tiny 2x2 RGBA buffer
    var buf = try rasterizer.PixelBuffer.init(testing.allocator, 2, 2, .{ 255, 0, 0, 255 });
    defer buf.deinit();

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    try encodeImage(output.writer(testing.allocator), &buf);
    const result = output.items;

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

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    try encodeImage(output.writer(testing.allocator), &buf);
    const result = output.items;

    try testing.expect(std.mem.indexOf(u8, result, "a=T") != null);
    try testing.expect(std.mem.indexOf(u8, result, "q=2") != null);
}

test "encodeImageReplace: includes image ID" {
    var buf = try rasterizer.PixelBuffer.init(testing.allocator, 1, 1, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    try encodeImageReplace(output.writer(testing.allocator), &buf, 42);
    const result = output.items;

    try testing.expect(std.mem.indexOf(u8, result, "i=42") != null);
}

test "deleteImage: produces valid delete sequence" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    try deleteImage(output.writer(testing.allocator), 7);
    const result = output.items;

    try testing.expect(std.mem.startsWith(u8, result, ESC_G));
    try testing.expect(std.mem.indexOf(u8, result, "a=d") != null);
    try testing.expect(std.mem.indexOf(u8, result, "i=7") != null);
}

test "cursorUp: emits ANSI escape" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    try cursorUp(output.writer(testing.allocator), 5);
    try testing.expectEqualStrings("\x1b[5A", output.items);
}

test "hideCursor and showCursor" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    try hideCursor(output.writer(testing.allocator));
    try testing.expectEqualStrings("\x1b[?25l", output.items);

    output.clearAndFree(testing.allocator);

    try showCursor(output.writer(testing.allocator));
    try testing.expectEqualStrings("\x1b[?25h", output.items);
}
