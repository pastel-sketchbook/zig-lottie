const std = @import("std");
const lottie = @import("zig-lottie");
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------
// RGBA Pixel Buffer
// ---------------------------------------------------------------

/// An RGBA pixel: [r, g, b, a] each 0-255.
pub const Pixel = [4]u8;

/// A mutable RGBA pixel buffer for rasterization.
pub const PixelBuffer = struct {
    allocator: Allocator,
    width: u32,
    height: u32,
    data: []u8,

    /// Create a new pixel buffer filled with a background color.
    pub fn init(allocator: Allocator, width: u32, height: u32, bg: Pixel) !PixelBuffer {
        const size = @as(usize, width) * @as(usize, height) * 4;
        const data = try allocator.alloc(u8, size);
        // Fill with background color
        var i: usize = 0;
        while (i < size) : (i += 4) {
            data[i] = bg[0];
            data[i + 1] = bg[1];
            data[i + 2] = bg[2];
            data[i + 3] = bg[3];
        }
        return PixelBuffer{
            .allocator = allocator,
            .width = width,
            .height = height,
            .data = data,
        };
    }

    pub fn deinit(self: *PixelBuffer) void {
        self.allocator.free(self.data);
    }

    /// Clear the buffer to a solid color.
    pub fn clear(self: *PixelBuffer, color: Pixel) void {
        var i: usize = 0;
        while (i < self.data.len) : (i += 4) {
            self.data[i] = color[0];
            self.data[i + 1] = color[1];
            self.data[i + 2] = color[2];
            self.data[i + 3] = color[3];
        }
    }

    /// Set a single pixel with alpha blending (source-over compositing).
    pub fn blendPixel(self: *PixelBuffer, x: i32, y: i32, color: Pixel) void {
        if (x < 0 or y < 0) return;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.width or uy >= self.height) return;

        const idx = (@as(usize, uy) * @as(usize, self.width) + @as(usize, ux)) * 4;
        const sa: u16 = color[3];
        if (sa == 0) return;
        if (sa == 255) {
            self.data[idx] = color[0];
            self.data[idx + 1] = color[1];
            self.data[idx + 2] = color[2];
            self.data[idx + 3] = 255;
            return;
        }

        // Source-over: out = src * sa + dst * (1 - sa)
        const inv_sa: u16 = 255 - sa;
        self.data[idx] = @intCast((sa * @as(u16, color[0]) + inv_sa * @as(u16, self.data[idx])) / 255);
        self.data[idx + 1] = @intCast((sa * @as(u16, color[1]) + inv_sa * @as(u16, self.data[idx + 1])) / 255);
        self.data[idx + 2] = @intCast((sa * @as(u16, color[2]) + inv_sa * @as(u16, self.data[idx + 2])) / 255);
        self.data[idx + 3] = @intCast(@min(255, @as(u16, self.data[idx + 3]) + sa - (sa * @as(u16, self.data[idx + 3])) / 255));
    }

    /// Get pixel value at (x, y), or null if out of bounds.
    pub fn getPixel(self: *const PixelBuffer, x: u32, y: u32) ?Pixel {
        if (x >= self.width or y >= self.height) return null;
        const idx = (@as(usize, y) * @as(usize, self.width) + @as(usize, x)) * 4;
        return .{ self.data[idx], self.data[idx + 1], self.data[idx + 2], self.data[idx + 3] };
    }
};

// ---------------------------------------------------------------
// Transform math
// ---------------------------------------------------------------

/// A 2D affine transform matrix: [a, b, c, d, tx, ty]
/// Maps point (x, y) to (a*x + c*y + tx, b*x + d*y + ty)
pub const Matrix = struct {
    a: f64 = 1,
    b: f64 = 0,
    c: f64 = 0,
    d: f64 = 1,
    tx: f64 = 0,
    ty: f64 = 0,

    pub const identity = Matrix{};

    /// Multiply this * other (this applied after other).
    pub fn multiply(self: Matrix, other: Matrix) Matrix {
        return Matrix{
            .a = self.a * other.a + self.c * other.b,
            .b = self.b * other.a + self.d * other.b,
            .c = self.a * other.c + self.c * other.d,
            .d = self.b * other.c + self.d * other.d,
            .tx = self.a * other.tx + self.c * other.ty + self.tx,
            .ty = self.b * other.tx + self.d * other.ty + self.ty,
        };
    }

    /// Create a translation matrix.
    pub fn translate(tx: f64, ty: f64) Matrix {
        return Matrix{ .tx = tx, .ty = ty };
    }

    /// Create a scale matrix.
    pub fn scale(sx: f64, sy: f64) Matrix {
        return Matrix{ .a = sx, .d = sy };
    }

    /// Create a rotation matrix (angle in radians).
    pub fn rotate(angle: f64) Matrix {
        const c = @cos(angle);
        const s = @sin(angle);
        return Matrix{ .a = c, .b = s, .c = -s, .d = c };
    }

    /// Transform a point.
    pub fn apply(self: Matrix, x: f64, y: f64) [2]f64 {
        return .{
            self.a * x + self.c * y + self.tx,
            self.b * x + self.d * y + self.ty,
        };
    }
};

/// Build a 2D affine matrix from a ResolvedTransform.
/// Lottie transform order: translate(-anchor) -> scale -> rotate -> translate(position)
pub fn matrixFromTransform(tr: lottie.ResolvedTransform) Matrix {
    const sx = tr.scale[0] / 100.0;
    const sy = tr.scale[1] / 100.0;
    const angle = tr.rotation * std.math.pi / 180.0;

    // Build in reverse application order (rightmost applied first):
    // result = translate(pos) * rotate(r) * scale(s) * translate(-anchor)
    var m = Matrix.translate(-tr.anchor[0], -tr.anchor[1]);
    m = Matrix.scale(sx, sy).multiply(m);
    m = Matrix.rotate(angle).multiply(m);
    m = Matrix.translate(tr.position[0], tr.position[1]).multiply(m);
    return m;
}

// ---------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------

/// Convert Lottie color [r,g,b,a] (0-1 floats) + opacity (0-100) to RGBA pixel.
pub fn colorToPixel(color: [4]f64, opacity: f64) Pixel {
    const a = std.math.clamp(color[3] * (opacity / 100.0), 0, 1);
    return .{
        @intFromFloat(std.math.clamp(color[0] * 255.0, 0, 255)),
        @intFromFloat(std.math.clamp(color[1] * 255.0, 0, 255)),
        @intFromFloat(std.math.clamp(color[2] * 255.0, 0, 255)),
        @intFromFloat(std.math.clamp(a * 255.0, 0, 255)),
    };
}

// ---------------------------------------------------------------
// Shape rasterizers
// ---------------------------------------------------------------

/// Draw a filled axis-aligned rectangle (before transform).
pub fn fillRect(buf: *PixelBuffer, cx: f64, cy: f64, w: f64, h: f64, color: Pixel, mat: Matrix) void {
    const half_w = w / 2.0;
    const half_h = h / 2.0;

    // Compute transformed bounding box
    const corners = [4][2]f64{
        mat.apply(cx - half_w, cy - half_h),
        mat.apply(cx + half_w, cy - half_h),
        mat.apply(cx + half_w, cy + half_h),
        mat.apply(cx - half_w, cy + half_h),
    };

    var min_x: f64 = corners[0][0];
    var max_x: f64 = corners[0][0];
    var min_y: f64 = corners[0][1];
    var max_y: f64 = corners[0][1];
    for (corners[1..]) |c| {
        min_x = @min(min_x, c[0]);
        max_x = @max(max_x, c[0]);
        min_y = @min(min_y, c[1]);
        max_y = @max(max_y, c[1]);
    }

    // Clamp to buffer
    const start_x: i32 = @intFromFloat(@max(0, @floor(min_x)));
    const end_x: i32 = @intFromFloat(@min(@as(f64, @floatFromInt(buf.width)), @ceil(max_x)));
    const start_y: i32 = @intFromFloat(@max(0, @floor(min_y)));
    const end_y: i32 = @intFromFloat(@min(@as(f64, @floatFromInt(buf.height)), @ceil(max_y)));

    // For each pixel in the bounding box, check if it's inside the transformed rectangle
    // using cross-product winding test against the 4 corners.
    var py = start_y;
    while (py < end_y) : (py += 1) {
        var px = start_x;
        while (px < end_x) : (px += 1) {
            const fx: f64 = @as(f64, @floatFromInt(px)) + 0.5;
            const fy: f64 = @as(f64, @floatFromInt(py)) + 0.5;
            if (pointInConvexQuad(fx, fy, corners)) {
                buf.blendPixel(px, py, color);
            }
        }
    }
}

/// Draw a filled ellipse.
pub fn fillEllipse(buf: *PixelBuffer, cx: f64, cy: f64, w: f64, h: f64, color: Pixel, mat: Matrix) void {
    const rx = w / 2.0;
    const ry = h / 2.0;
    if (rx <= 0 or ry <= 0) return;

    // Sample bounding box of the transformed ellipse
    // Generate points on the ellipse boundary to find bounds
    const steps = 32;
    var min_x: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    var min_y: f64 = std.math.inf(f64);
    var max_y: f64 = -std.math.inf(f64);

    for (0..steps) |i| {
        const angle = @as(f64, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f64, @floatFromInt(steps));
        const ex = cx + rx * @cos(angle);
        const ey = cy + ry * @sin(angle);
        const p = mat.apply(ex, ey);
        min_x = @min(min_x, p[0]);
        max_x = @max(max_x, p[0]);
        min_y = @min(min_y, p[1]);
        max_y = @max(max_y, p[1]);
    }

    const start_x: i32 = @intFromFloat(@max(0, @floor(min_x)));
    const end_x: i32 = @intFromFloat(@min(@as(f64, @floatFromInt(buf.width)), @ceil(max_x)));
    const start_y: i32 = @intFromFloat(@max(0, @floor(min_y)));
    const end_y: i32 = @intFromFloat(@min(@as(f64, @floatFromInt(buf.height)), @ceil(max_y)));

    // For each pixel, inverse-transform back to local space and test ellipse equation
    // We need the inverse of the matrix. For affine transforms: inv exists if det != 0.
    const det = mat.a * mat.d - mat.b * mat.c;
    if (@abs(det) < 1e-12) return;
    const inv_det = 1.0 / det;
    const inv = Matrix{
        .a = mat.d * inv_det,
        .b = -mat.b * inv_det,
        .c = -mat.c * inv_det,
        .d = mat.a * inv_det,
        .tx = (mat.c * mat.ty - mat.d * mat.tx) * inv_det,
        .ty = (mat.b * mat.tx - mat.a * mat.ty) * inv_det,
    };

    var py = start_y;
    while (py < end_y) : (py += 1) {
        var px = start_x;
        while (px < end_x) : (px += 1) {
            const fx: f64 = @as(f64, @floatFromInt(px)) + 0.5;
            const fy: f64 = @as(f64, @floatFromInt(py)) + 0.5;
            const local = inv.apply(fx, fy);
            const dx = (local[0] - cx) / rx;
            const dy = (local[1] - cy) / ry;
            if (dx * dx + dy * dy <= 1.0) {
                buf.blendPixel(px, py, color);
            }
        }
    }
}

/// Test if point (px, py) is inside a convex quadrilateral defined by 4 corners (CCW or CW).
fn pointInConvexQuad(px: f64, py: f64, corners: [4][2]f64) bool {
    // Cross product sign must be consistent for all edges.
    var positive: bool = false;
    var negative: bool = false;
    for (0..4) |i| {
        const j = (i + 1) % 4;
        const ex = corners[j][0] - corners[i][0];
        const ey = corners[j][1] - corners[i][1];
        const dx = px - corners[i][0];
        const dy = py - corners[i][1];
        const cross = ex * dy - ey * dx;
        if (cross > 0) positive = true;
        if (cross < 0) negative = true;
        if (positive and negative) return false;
    }
    return true;
}

// ---------------------------------------------------------------
// Render a resolved frame
// ---------------------------------------------------------------

/// Render a compiled frame to a pixel buffer.
/// The `canvas_mat` is prepended to every layer transform (typically a scale
/// matrix that maps animation coordinates to output pixel coordinates).
/// Layer opacity is applied to all shapes in the layer.
/// Parent-child layer relationships are resolved by walking the parent chain.
pub fn renderFrame(buf: *PixelBuffer, frame: *const lottie.CompiledFrame, canvas_mat: Matrix) void {
    // Render layers in reverse order (bottom layer first in Lottie spec).
    var li: usize = frame.layers.len;
    while (li > 0) {
        li -= 1;
        const layer = &frame.layers[li];
        if (!layer.visible) continue;

        // Build world transform by walking the parent chain.
        const world = resolveLayerWorldTransform(frame.layers, layer, canvas_mat);

        renderShapes(buf, layer.shapes, world.mat, world.opacity);
    }
}

const WorldTransform = struct {
    mat: Matrix,
    opacity: f64,
};

/// Walk the parent chain to compose the full world transform for a layer.
/// Applies transforms in order: canvas -> ... -> grandparent -> parent -> self.
fn resolveLayerWorldTransform(layers: []const lottie.ResolvedLayer, layer: *const lottie.ResolvedLayer, canvas_mat: Matrix) WorldTransform {
    // Collect the chain from self up to root (max 32 deep to prevent cycles).
    var chain: [32]*const lottie.ResolvedLayer = undefined;
    var depth: usize = 0;
    var current: ?*const lottie.ResolvedLayer = layer;

    while (current) |cur| {
        if (depth >= 32) break; // guard against cycles
        chain[depth] = cur;
        depth += 1;
        current = if (cur.parent) |pid| findLayerByIndex(layers, pid) else null;
    }

    // Apply transforms from root (last in chain) down to self (first).
    var mat = canvas_mat;
    var opacity: f64 = 1.0;
    var i: usize = depth;
    while (i > 0) {
        i -= 1;
        if (chain[i].transform) |tr| {
            mat = mat.multiply(matrixFromTransform(tr));
            opacity *= tr.opacity / 100.0;
        }
    }

    return .{ .mat = mat, .opacity = opacity };
}

/// Find a layer by its index field.
fn findLayerByIndex(layers: []const lottie.ResolvedLayer, index: i64) ?*const lottie.ResolvedLayer {
    for (layers) |*l| {
        if (l.index) |idx| {
            if (idx == index) return l;
        }
    }
    return null;
}

/// Render a slice of resolved shapes.
fn renderShapes(buf: *PixelBuffer, shapes: []const lottie.ResolvedShape, parent_mat: Matrix, parent_opacity: f64) void {
    // In Lottie, shapes within a group share fill/stroke context.
    // We render in order: geometry shapes use the last seen fill/stroke.
    // Simplified approach: collect the current fill context, then render geometry.

    // First pass: find the group's fill/stroke (usually last in the items list
    // before the transform). We use a simple approach: scan for fill/stroke.
    var fill_color: ?Pixel = null;
    var stroke_color: ?Pixel = null;
    var stroke_width: f64 = 1;
    var group_transform = Matrix.identity;
    var has_group_transform = false;

    for (shapes) |shape| {
        switch (shape.ty) {
            .fill => {
                if (shape.color) |c| {
                    const opacity = shape.opacity orelse 100;
                    fill_color = colorToPixel(c, opacity * parent_opacity);
                }
            },
            .stroke => {
                if (shape.color) |c| {
                    const opacity = shape.opacity orelse 100;
                    stroke_color = colorToPixel(c, opacity * parent_opacity);
                }
                stroke_width = shape.stroke_width orelse 1;
            },
            .transform => {
                if (shape.transform) |tr| {
                    group_transform = matrixFromTransform(tr);
                    has_group_transform = true;
                }
            },
            else => {},
        }
    }

    const mat = if (has_group_transform)
        parent_mat.multiply(group_transform)
    else
        parent_mat;

    // Second pass: render geometry shapes
    for (shapes) |shape| {
        switch (shape.ty) {
            .rectangle => {
                if (fill_color) |fc| {
                    const sz = shape.size orelse continue;
                    const pos = shape.position orelse [2]f64{ 0, 0 };
                    fillRect(buf, pos[0], pos[1], sz[0], sz[1], fc, mat);
                }
                if (stroke_color) |sc| {
                    const sz = shape.size orelse continue;
                    const pos = shape.position orelse [2]f64{ 0, 0 };
                    strokeRect(buf, pos[0], pos[1], sz[0], sz[1], sc, stroke_width, mat);
                }
            },
            .ellipse => {
                if (fill_color) |fc| {
                    const sz = shape.size orelse continue;
                    const pos = shape.position orelse [2]f64{ 0, 0 };
                    fillEllipse(buf, pos[0], pos[1], sz[0], sz[1], fc, mat);
                }
            },
            .group => {
                renderShapes(buf, shape.items, mat, parent_opacity);
            },
            else => {},
        }
    }
}

/// Draw a stroked rectangle outline.
pub fn strokeRect(buf: *PixelBuffer, cx: f64, cy: f64, w: f64, h: f64, color: Pixel, width: f64, mat: Matrix) void {
    // Draw 4 edges as thin filled rects
    const half_w = w / 2.0;
    const half_h = h / 2.0;
    const hw = width / 2.0;

    // Top edge
    fillRect(buf, cx, cy - half_h, w + width, width, color, mat);
    // Bottom edge
    fillRect(buf, cx, cy + half_h, w + width, width, color, mat);
    // Left edge
    fillRect(buf, cx - half_w, cy, width, h - width, color, mat);
    // Right edge
    fillRect(buf, cx + half_w, cy, width, h - width, color, mat);
    _ = hw;
}

// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

const testing = std.testing;

test "PixelBuffer: init and clear" {
    var buf = try PixelBuffer.init(testing.allocator, 4, 4, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // Check initial fill
    const p = buf.getPixel(0, 0).?;
    try testing.expectEqual(@as(u8, 0), p[0]);
    try testing.expectEqual(@as(u8, 0), p[1]);
    try testing.expectEqual(@as(u8, 0), p[2]);
    try testing.expectEqual(@as(u8, 255), p[3]);

    // Clear to white
    buf.clear(.{ 255, 255, 255, 255 });
    const p2 = buf.getPixel(2, 2).?;
    try testing.expectEqual(@as(u8, 255), p2[0]);
}

test "PixelBuffer: blendPixel opaque" {
    var buf = try PixelBuffer.init(testing.allocator, 4, 4, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    buf.blendPixel(1, 1, .{ 255, 0, 0, 255 });
    const p = buf.getPixel(1, 1).?;
    try testing.expectEqual(@as(u8, 255), p[0]);
    try testing.expectEqual(@as(u8, 0), p[1]);
    try testing.expectEqual(@as(u8, 0), p[2]);
}

test "PixelBuffer: blendPixel semi-transparent" {
    var buf = try PixelBuffer.init(testing.allocator, 4, 4, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // 50% red over black should give ~128 red
    buf.blendPixel(1, 1, .{ 255, 0, 0, 128 });
    const p = buf.getPixel(1, 1).?;
    try testing.expect(p[0] >= 126 and p[0] <= 130); // ~128
    try testing.expectEqual(@as(u8, 0), p[1]);
}

test "PixelBuffer: blendPixel out of bounds is no-op" {
    var buf = try PixelBuffer.init(testing.allocator, 4, 4, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    buf.blendPixel(-1, 0, .{ 255, 0, 0, 255 });
    buf.blendPixel(4, 0, .{ 255, 0, 0, 255 });
    buf.blendPixel(0, -1, .{ 255, 0, 0, 255 });
    buf.blendPixel(0, 4, .{ 255, 0, 0, 255 });
    // Should not crash, buffer unchanged
    const p = buf.getPixel(0, 0).?;
    try testing.expectEqual(@as(u8, 0), p[0]);
}

test "Matrix: identity" {
    const m = Matrix.identity;
    const p = m.apply(10, 20);
    try testing.expectEqual(@as(f64, 10.0), p[0]);
    try testing.expectEqual(@as(f64, 20.0), p[1]);
}

test "Matrix: translate" {
    const m = Matrix.translate(100, 200);
    const p = m.apply(10, 20);
    try testing.expectEqual(@as(f64, 110.0), p[0]);
    try testing.expectEqual(@as(f64, 220.0), p[1]);
}

test "Matrix: scale" {
    const m = Matrix.scale(2, 3);
    const p = m.apply(10, 20);
    try testing.expectEqual(@as(f64, 20.0), p[0]);
    try testing.expectEqual(@as(f64, 60.0), p[1]);
}

test "Matrix: rotate 90 degrees" {
    const m = Matrix.rotate(std.math.pi / 2.0);
    const p = m.apply(1, 0);
    try testing.expectApproxEqAbs(@as(f64, 0.0), p[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), p[1], 0.001);
}

test "Matrix: multiply translate then scale" {
    const s = Matrix.scale(2, 2);
    const t = Matrix.translate(10, 20);
    // scale applied first, then translate: result = t * s
    const m = t.multiply(s);
    const p = m.apply(5, 5);
    // 5 * 2 = 10, then + 10 = 20
    try testing.expectEqual(@as(f64, 20.0), p[0]);
    // 5 * 2 = 10, then + 20 = 30
    try testing.expectEqual(@as(f64, 30.0), p[1]);
}

test "matrixFromTransform: identity transform" {
    const tr = lottie.ResolvedTransform{
        .anchor = .{ 0, 0, 0 },
        .position = .{ 0, 0, 0 },
        .scale = .{ 100, 100, 100 },
        .rotation = 0,
        .opacity = 100,
    };
    const m = matrixFromTransform(tr);
    const p = m.apply(50, 50);
    try testing.expectApproxEqAbs(@as(f64, 50.0), p[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 50.0), p[1], 0.001);
}

test "matrixFromTransform: position offset" {
    const tr = lottie.ResolvedTransform{
        .anchor = .{ 0, 0, 0 },
        .position = .{ 100, 200, 0 },
        .scale = .{ 100, 100, 100 },
        .rotation = 0,
        .opacity = 100,
    };
    const m = matrixFromTransform(tr);
    const p = m.apply(0, 0);
    try testing.expectApproxEqAbs(@as(f64, 100.0), p[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 200.0), p[1], 0.001);
}

test "matrixFromTransform: anchor point offset" {
    const tr = lottie.ResolvedTransform{
        .anchor = .{ 50, 50, 0 },
        .position = .{ 50, 50, 0 },
        .scale = .{ 100, 100, 100 },
        .rotation = 0,
        .opacity = 100,
    };
    const m = matrixFromTransform(tr);
    // Point at (50,50) maps to: translate(-50,-50) -> (0,0), then translate(+50,+50) -> (50,50)
    const p = m.apply(50, 50);
    try testing.expectApproxEqAbs(@as(f64, 50.0), p[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 50.0), p[1], 0.001);
    // Point at (0,0) maps to: translate(-50,-50) -> (-50,-50), then translate(+50,+50) -> (0,0)
    const p2 = m.apply(0, 0);
    try testing.expectApproxEqAbs(@as(f64, 0.0), p2[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), p2[1], 0.001);
}

test "colorToPixel: red at full opacity" {
    const px = colorToPixel(.{ 1, 0, 0, 1 }, 100);
    try testing.expectEqual(@as(u8, 255), px[0]);
    try testing.expectEqual(@as(u8, 0), px[1]);
    try testing.expectEqual(@as(u8, 0), px[2]);
    try testing.expectEqual(@as(u8, 255), px[3]);
}

test "colorToPixel: half opacity" {
    const px = colorToPixel(.{ 0, 1, 0, 1 }, 50);
    try testing.expectEqual(@as(u8, 0), px[0]);
    try testing.expectEqual(@as(u8, 255), px[1]);
    try testing.expectEqual(@as(u8, 0), px[2]);
    try testing.expect(px[3] >= 126 and px[3] <= 128); // ~127
}

test "fillRect: axis-aligned rectangle fills pixels" {
    var buf = try PixelBuffer.init(testing.allocator, 10, 10, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // Fill a 4x4 rect centered at (5, 5)
    fillRect(&buf, 5, 5, 4, 4, .{ 255, 0, 0, 255 }, Matrix.identity);

    // Center pixel should be red
    const center = buf.getPixel(5, 5).?;
    try testing.expectEqual(@as(u8, 255), center[0]);

    // Pixel at (3, 3) is at the edge (5-2=3, 5-2=3) - should be red
    const edge = buf.getPixel(3, 3).?;
    try testing.expectEqual(@as(u8, 255), edge[0]);

    // Pixel at (0, 0) should still be black
    const corner = buf.getPixel(0, 0).?;
    try testing.expectEqual(@as(u8, 0), corner[0]);
}

test "fillEllipse: centered ellipse fills pixels" {
    var buf = try PixelBuffer.init(testing.allocator, 20, 20, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // Fill a 10x10 ellipse centered at (10, 10)
    fillEllipse(&buf, 10, 10, 10, 10, .{ 0, 255, 0, 255 }, Matrix.identity);

    // Center should be green
    const center = buf.getPixel(10, 10).?;
    try testing.expectEqual(@as(u8, 0), center[0]);
    try testing.expectEqual(@as(u8, 255), center[1]);

    // Corner should still be black
    const corner = buf.getPixel(0, 0).?;
    try testing.expectEqual(@as(u8, 0), corner[1]);
}

test "fillRect: with scale transform" {
    var buf = try PixelBuffer.init(testing.allocator, 20, 20, .{ 0, 0, 0, 255 });
    defer buf.deinit();

    // 2x2 rect at origin, scaled 5x -> fills 10x10 area
    const mat = Matrix.scale(5, 5);
    fillRect(&buf, 0, 0, 2, 2, .{ 255, 255, 0, 255 }, mat);

    // Pixel at (0, 0) should be yellow (inside the scaled rect)
    const p0 = buf.getPixel(0, 0).?;
    try testing.expectEqual(@as(u8, 255), p0[0]);
    try testing.expectEqual(@as(u8, 255), p0[1]);
}

test "pointInConvexQuad: basic square" {
    const corners = [4][2]f64{
        .{ 0, 0 },
        .{ 10, 0 },
        .{ 10, 10 },
        .{ 0, 10 },
    };
    try testing.expect(pointInConvexQuad(5, 5, corners));
    try testing.expect(!pointInConvexQuad(-1, 5, corners));
    try testing.expect(!pointInConvexQuad(11, 5, corners));
}
