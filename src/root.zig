const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Semantic version of the zig-lottie library.
pub const version = "0.1.0";

// ---------------------------------------------------------------
// Lottie Schema Types
// ---------------------------------------------------------------

/// A 2D point value [x, y].
pub const Vec2 = [2]f64;

/// A single keyframe in an animated property.
pub const Keyframe = struct {
    /// Keyframe time (frame number).
    time: f64,
    /// Keyframe value (scalar).
    value: f64,
    /// Bezier easing out handle [x, y], or null for linear/hold.
    ease_out: ?Vec2,
    /// Bezier easing in handle [x, y], or null for linear/hold.
    ease_in: ?Vec2,
    /// Hold keyframe (no interpolation to next).
    hold: bool,
};

/// A single keyframe for a multi-dimensional animated property.
pub const MultiKeyframe = struct {
    /// Keyframe time (frame number).
    time: f64,
    /// Keyframe values (e.g. [x, y] for position, [sx, sy] for scale).
    values: []const f64,
    /// Bezier easing out handle [x, y], or null for linear/hold.
    ease_out: ?Vec2,
    /// Bezier easing in handle [x, y], or null for linear/hold.
    ease_in: ?Vec2,
    /// Hold keyframe.
    hold: bool,
};

/// An animated property: either a static value or a sequence of keyframes.
pub const AnimatedValue = union(enum) {
    /// Static (non-animated) scalar value.
    static: f64,
    /// Animated scalar with keyframes.
    keyframed: []const Keyframe,
};

/// A multi-dimensional animated property (position, scale, anchor point).
pub const AnimatedMulti = union(enum) {
    /// Static multi-dimensional value.
    static: []const f64,
    /// Animated with keyframes.
    keyframed: []const MultiKeyframe,
};

/// Layer transform (`ks` in the Lottie spec).
pub const Transform = struct {
    /// Anchor point (`a`).
    anchor: ?AnimatedMulti,
    /// Position (`p`).
    position: ?AnimatedMulti,
    /// Scale (`s`) — in percentage (100 = 1x).
    scale: ?AnimatedMulti,
    /// Rotation in degrees (`r`).
    rotation: ?AnimatedValue,
    /// Opacity 0-100 (`o`).
    opacity: ?AnimatedValue,
};

/// Lottie shape types (matches the `ty` field in the shape spec).
pub const ShapeType = enum {
    group, // "gr"
    rectangle, // "rc"
    ellipse, // "el"
    path, // "sh"
    fill, // "fl"
    stroke, // "st"
    transform, // "tr"
    gradient_fill, // "gf"
    gradient_stroke, // "gs"
    merge, // "mm"
    trim, // "tm"
    round_corners, // "rd"
    repeater, // "rp"
    star, // "sr"
    unknown,
};

/// Color represented as [r, g, b] with values 0.0-1.0.
pub const Color = [3]f64;

/// A shape element within a shape layer.
pub const Shape = struct {
    /// Shape type.
    ty: ShapeType,
    /// Shape name (optional).
    name: ?[]const u8,
    /// Sub-shapes for groups.
    items: []const Shape,
    // -- Rectangle fields --
    /// Rectangle size [w, h].
    size: ?AnimatedMulti,
    /// Rectangle corner position.
    position: ?AnimatedMulti,
    /// Rectangle corner roundness.
    roundness: ?AnimatedValue,
    // -- Ellipse fields --
    // (reuses size and position)
    // -- Fill fields --
    /// Fill/stroke color.
    color: ?AnimatedMulti,
    /// Fill/stroke opacity (0-100).
    opacity: ?AnimatedValue,
    // -- Stroke fields --
    /// Stroke width.
    stroke_width: ?AnimatedValue,
    // -- Path fields --
    // Path vertices stored as raw JSON for now (complex bezier data).
    // TODO: parse into structured Bezier path type.
    // -- Transform fields --
    /// Shape-level transform.
    transform: ?Transform,
};

/// Lottie layer types (matches the `ty` field in the spec).
pub const LayerType = enum(u8) {
    precomp = 0,
    solid = 1,
    image = 2,
    null_object = 3,
    shape = 4,
    text = 5,
    audio = 6,
    video_placeholder = 7,
    image_sequence = 8,
    video = 9,
    image_placeholder = 10,
    guide = 11,
    adjustment = 12,
    camera = 13,
    light = 14,
    data = 15,
    _,
};

/// A single layer in the animation.
pub const Layer = struct {
    /// Layer type.
    ty: LayerType,
    /// Layer name (optional in spec).
    name: ?[]const u8,
    /// Layer index.
    index: ?i64,
    /// Parent layer index.
    parent: ?i64,
    /// In-point (start frame).
    in_point: f64,
    /// Out-point (end frame).
    out_point: f64,
    /// Layer transform.
    transform: ?Transform,
    /// Shapes (only for shape layers, ty=4).
    shapes: []const Shape,
};

/// Top-level parsed Lottie animation.
pub const Animation = struct {
    allocator: Allocator,
    /// Lottie format version string (e.g. "5.7.1").
    version_str: []const u8,
    /// Frames per second.
    frame_rate: f64,
    /// Start frame.
    in_point: f64,
    /// End frame.
    out_point: f64,
    /// Canvas width.
    width: u32,
    /// Canvas height.
    height: u32,
    /// Animation name (optional).
    name: ?[]const u8,
    /// Layers in the animation.
    layers: []const Layer,

    /// Free all memory owned by this Animation.
    pub fn deinit(self: *const Animation) void {
        for (self.layers) |layer| {
            freeShapes(self.allocator, layer.shapes);
            freeTransform(self.allocator, layer.transform);
            if (layer.name) |n| self.allocator.free(n);
        }
        self.allocator.free(self.layers);
        if (self.name) |n| self.allocator.free(n);
        self.allocator.free(self.version_str);
    }

    /// Duration in seconds.
    pub fn duration(self: *const Animation) f64 {
        return (self.out_point - self.in_point) / self.frame_rate;
    }
};

// ---------------------------------------------------------------
// Memory free helpers
// ---------------------------------------------------------------

fn freeAnimatedValue(allocator: Allocator, av: ?AnimatedValue) void {
    const v = av orelse return;
    switch (v) {
        .keyframed => |kfs| allocator.free(kfs),
        .static => {},
    }
}

fn freeAnimatedMulti(allocator: Allocator, am: ?AnimatedMulti) void {
    const v = am orelse return;
    switch (v) {
        .static => |s| allocator.free(s),
        .keyframed => |kfs| {
            for (kfs) |kf| allocator.free(kf.values);
            allocator.free(kfs);
        },
    }
}

fn freeTransform(allocator: Allocator, t: ?Transform) void {
    const tr = t orelse return;
    freeAnimatedMulti(allocator, tr.anchor);
    freeAnimatedMulti(allocator, tr.position);
    freeAnimatedMulti(allocator, tr.scale);
    freeAnimatedValue(allocator, tr.rotation);
    freeAnimatedValue(allocator, tr.opacity);
}

fn freeShapes(allocator: Allocator, shapes: []const Shape) void {
    for (shapes) |shape| {
        freeShapes(allocator, shape.items);
        freeAnimatedMulti(allocator, shape.size);
        freeAnimatedMulti(allocator, shape.position);
        freeAnimatedValue(allocator, shape.roundness);
        freeAnimatedMulti(allocator, shape.color);
        freeAnimatedValue(allocator, shape.opacity);
        freeAnimatedValue(allocator, shape.stroke_width);
        freeTransform(allocator, shape.transform);
        if (shape.name) |n| allocator.free(n);
    }
    allocator.free(shapes);
}

// ---------------------------------------------------------------
// Errors
// ---------------------------------------------------------------

/// Errors that can occur during Lottie parsing.
pub const ParseError = error{
    InvalidJson,
    MissingRequiredField,
    UnsupportedVersion,
    OutOfMemory,
};

// ---------------------------------------------------------------
// Parser
// ---------------------------------------------------------------

/// Parse a Lottie JSON buffer into an Animation.
///
/// The caller owns the returned Animation and must call `deinit()` to free it.
pub fn parse(allocator: Allocator, json_buf: []const u8) ParseError!Animation {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_buf,
        .{},
    ) catch return ParseError.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return ParseError.InvalidJson;

    const obj = root.object;

    // Required top-level fields
    const v_val = obj.get("v") orelse return ParseError.MissingRequiredField;
    const fr_val = obj.get("fr") orelse return ParseError.MissingRequiredField;
    const ip_val = obj.get("ip") orelse return ParseError.MissingRequiredField;
    const op_val = obj.get("op") orelse return ParseError.MissingRequiredField;
    const w_val = obj.get("w") orelse return ParseError.MissingRequiredField;
    const h_val = obj.get("h") orelse return ParseError.MissingRequiredField;

    const version_str = switch (v_val) {
        .string => |s| allocator.dupe(u8, s) catch return ParseError.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    errdefer allocator.free(version_str);

    // Optional name
    const anim_name: ?[]const u8 = if (obj.get("nm")) |nm_val| switch (nm_val) {
        .string => |s| allocator.dupe(u8, s) catch return ParseError.OutOfMemory,
        else => null,
    } else null;
    errdefer if (anim_name) |n| allocator.free(n);

    // Parse layers array
    const layers_val = obj.get("layers");
    const layers = try parseLayers(allocator, layers_val);
    errdefer {
        for (layers) |layer| {
            freeShapes(allocator, layer.shapes);
            freeTransform(allocator, layer.transform);
            if (layer.name) |n| allocator.free(n);
        }
        allocator.free(layers);
    }

    return Animation{
        .allocator = allocator,
        .version_str = version_str,
        .frame_rate = jsonFloat(fr_val) orelse return ParseError.InvalidJson,
        .in_point = jsonFloat(ip_val) orelse return ParseError.InvalidJson,
        .out_point = jsonFloat(op_val) orelse return ParseError.InvalidJson,
        .width = jsonUint(u32, w_val) orelse return ParseError.InvalidJson,
        .height = jsonUint(u32, h_val) orelse return ParseError.InvalidJson,
        .name = anim_name,
        .layers = layers,
    };
}

/// Parse the `layers` array from a JSON value.
fn parseLayers(allocator: Allocator, layers_val: ?std.json.Value) ParseError![]Layer {
    const arr = if (layers_val) |v| switch (v) {
        .array => |a| a,
        else => return ParseError.InvalidJson,
    } else return allocator.alloc(Layer, 0) catch return ParseError.OutOfMemory;

    var layers: std.ArrayList(Layer) = .empty;
    errdefer {
        for (layers.items) |layer| {
            freeShapes(allocator, layer.shapes);
            freeTransform(allocator, layer.transform);
            if (layer.name) |n| allocator.free(n);
        }
        layers.deinit(allocator);
    }

    for (arr.items) |item| {
        if (item != .object) return ParseError.InvalidJson;
        const layer_obj = item.object;

        const ty_val = layer_obj.get("ty") orelse return ParseError.MissingRequiredField;
        const ty_int = jsonInt(ty_val) orelse return ParseError.InvalidJson;

        const layer_name: ?[]const u8 = if (layer_obj.get("nm")) |nm| switch (nm) {
            .string => |s| allocator.dupe(u8, s) catch return ParseError.OutOfMemory,
            else => null,
        } else null;
        errdefer if (layer_name) |n| allocator.free(n);

        const layer_ip = layer_obj.get("ip");
        const layer_op = layer_obj.get("op");

        // Parse transform (`ks` field)
        const transform = if (layer_obj.get("ks")) |ks_val|
            try parseTransform(allocator, ks_val)
        else
            null;
        errdefer freeTransform(allocator, transform);

        // Parse shapes (`shapes` field, only relevant for shape layers ty=4)
        const shapes = if (layer_obj.get("shapes")) |shapes_val|
            try parseShapes(allocator, shapes_val)
        else
            allocator.alloc(Shape, 0) catch return ParseError.OutOfMemory;
        errdefer freeShapes(allocator, shapes);

        layers.append(allocator, .{
            .ty = @enumFromInt(@as(u8, @intCast(std.math.clamp(ty_int, 0, 255)))),
            .name = layer_name,
            .index = if (layer_obj.get("ind")) |ind| jsonInt(ind) else null,
            .parent = if (layer_obj.get("parent")) |p| jsonInt(p) else null,
            .in_point = if (layer_ip) |ip| jsonFloat(ip) orelse 0 else 0,
            .out_point = if (layer_op) |op| jsonFloat(op) orelse 0 else 0,
            .transform = transform,
            .shapes = shapes,
        }) catch return ParseError.OutOfMemory;
    }

    return layers.toOwnedSlice(allocator) catch return ParseError.OutOfMemory;
}

// ---------------------------------------------------------------
// Transform parser
// ---------------------------------------------------------------

/// Parse a Transform from a JSON object value (`ks`).
fn parseTransform(allocator: Allocator, val: std.json.Value) ParseError!Transform {
    if (val != .object) return ParseError.InvalidJson;
    const obj = val.object;

    const anchor = if (obj.get("a")) |a| try parseAnimatedMulti(allocator, a) else null;
    errdefer freeAnimatedMulti(allocator, anchor);

    const position = if (obj.get("p")) |p| try parseAnimatedMulti(allocator, p) else null;
    errdefer freeAnimatedMulti(allocator, position);

    const scale = if (obj.get("s")) |s| try parseAnimatedMulti(allocator, s) else null;
    errdefer freeAnimatedMulti(allocator, scale);

    const rotation = if (obj.get("r")) |r| try parseAnimatedScalar(allocator, r) else null;
    errdefer freeAnimatedValue(allocator, rotation);

    const opacity = if (obj.get("o")) |o| try parseAnimatedScalar(allocator, o) else null;
    errdefer freeAnimatedValue(allocator, opacity);

    return Transform{
        .anchor = anchor,
        .position = position,
        .scale = scale,
        .rotation = rotation,
        .opacity = opacity,
    };
}

// ---------------------------------------------------------------
// Animated property parsers
// ---------------------------------------------------------------

/// Parse an animated scalar property.
/// Lottie format: `{ "a": 0|1, "k": <value_or_keyframes> }`
fn parseAnimatedScalar(allocator: Allocator, val: std.json.Value) ParseError!AnimatedValue {
    if (val != .object) return ParseError.InvalidJson;
    const obj = val.object;

    const animated = if (obj.get("a")) |a| (jsonInt(a) orelse 0) == 1 else false;
    const k_val = obj.get("k") orelse return ParseError.MissingRequiredField;

    if (!animated) {
        // Static value: `k` is a number or a single-element array
        const v = jsonFloat(k_val) orelse blk: {
            // Could be a single-element array like [100]
            if (k_val == .array) {
                if (k_val.array.items.len > 0) {
                    break :blk jsonFloat(k_val.array.items[0]);
                }
            }
            break :blk null;
        };
        return AnimatedValue{ .static = v orelse 0 };
    }

    // Animated: `k` is an array of keyframe objects
    if (k_val != .array) return ParseError.InvalidJson;
    const arr = k_val.array;

    var keyframes: std.ArrayList(Keyframe) = .empty;
    errdefer allocator.free(keyframes.items);

    for (arr.items) |kf_val| {
        if (kf_val != .object) return ParseError.InvalidJson;
        const kf_obj = kf_val.object;

        const t = if (kf_obj.get("t")) |t_val| jsonFloat(t_val) orelse 0 else 0;
        const s_arr = kf_obj.get("s");
        const value = if (s_arr) |s_val| blk: {
            if (s_val == .array and s_val.array.items.len > 0) {
                break :blk jsonFloat(s_val.array.items[0]) orelse 0;
            }
            break :blk jsonFloat(s_val) orelse 0;
        } else 0;

        const ease_out = parseEaseHandle(kf_obj.get("o"));
        const ease_in = parseEaseHandle(kf_obj.get("i"));
        const hold = if (kf_obj.get("h")) |h| (jsonInt(h) orelse 0) == 1 else false;

        keyframes.append(allocator, .{
            .time = t,
            .value = value,
            .ease_out = ease_out,
            .ease_in = ease_in,
            .hold = hold,
        }) catch return ParseError.OutOfMemory;
    }

    return AnimatedValue{ .keyframed = keyframes.toOwnedSlice(allocator) catch return ParseError.OutOfMemory };
}

/// Parse an animated multi-dimensional property.
/// Lottie format: `{ "a": 0|1, "k": <value_or_keyframes> }`
fn parseAnimatedMulti(allocator: Allocator, val: std.json.Value) ParseError!AnimatedMulti {
    if (val != .object) return ParseError.InvalidJson;
    const obj = val.object;

    const animated = if (obj.get("a")) |a| (jsonInt(a) orelse 0) == 1 else false;
    const k_val = obj.get("k") orelse return ParseError.MissingRequiredField;

    if (!animated) {
        // Static: `k` is an array of numbers [x, y, ...]
        if (k_val == .array) {
            const values = try jsonFloatArray(allocator, k_val.array);
            return AnimatedMulti{ .static = values };
        }
        // Single number — wrap in array
        const v = jsonFloat(k_val) orelse 0;
        const values = allocator.alloc(f64, 1) catch return ParseError.OutOfMemory;
        values[0] = v;
        return AnimatedMulti{ .static = values };
    }

    // Animated: `k` is an array of keyframe objects
    if (k_val != .array) return ParseError.InvalidJson;
    const arr = k_val.array;

    var keyframes: std.ArrayList(MultiKeyframe) = .empty;
    errdefer {
        for (keyframes.items) |kf| allocator.free(kf.values);
        keyframes.deinit(allocator);
    }

    for (arr.items) |kf_val| {
        if (kf_val != .object) return ParseError.InvalidJson;
        const kf_obj = kf_val.object;

        const t = if (kf_obj.get("t")) |t_val| jsonFloat(t_val) orelse 0 else 0;
        const values = if (kf_obj.get("s")) |s_val| blk: {
            if (s_val == .array) {
                break :blk try jsonFloatArray(allocator, s_val.array);
            }
            break :blk allocator.alloc(f64, 0) catch return ParseError.OutOfMemory;
        } else allocator.alloc(f64, 0) catch return ParseError.OutOfMemory;

        const ease_out = parseEaseHandle(kf_obj.get("o"));
        const ease_in = parseEaseHandle(kf_obj.get("i"));
        const hold = if (kf_obj.get("h")) |h| (jsonInt(h) orelse 0) == 1 else false;

        keyframes.append(allocator, .{
            .time = t,
            .values = values,
            .ease_out = ease_out,
            .ease_in = ease_in,
            .hold = hold,
        }) catch return ParseError.OutOfMemory;
    }

    return AnimatedMulti{ .keyframed = keyframes.toOwnedSlice(allocator) catch return ParseError.OutOfMemory };
}

/// Parse a bezier easing handle from `{ "x": [...], "y": [...] }`.
/// Returns [x, y] or null.
fn parseEaseHandle(val: ?std.json.Value) ?Vec2 {
    const obj_val = val orelse return null;
    if (obj_val != .object) return null;
    const obj = obj_val.object;

    const x_val = obj.get("x") orelse return null;
    const y_val = obj.get("y") orelse return null;

    const x = easeComponent(x_val) orelse return null;
    const y = easeComponent(y_val) orelse return null;

    return Vec2{ x, y };
}

/// Extract a single float from a number or first element of an array.
fn easeComponent(val: std.json.Value) ?f64 {
    if (jsonFloat(val)) |f| return f;
    if (val == .array and val.array.items.len > 0) {
        return jsonFloat(val.array.items[0]);
    }
    return null;
}

// ---------------------------------------------------------------
// Shape parser
// ---------------------------------------------------------------

/// Parse the `shapes` array from a JSON value.
fn parseShapes(allocator: Allocator, val: std.json.Value) ParseError![]Shape {
    if (val != .array) return ParseError.InvalidJson;
    const arr = val.array;

    var shapes: std.ArrayList(Shape) = .empty;
    errdefer {
        for (shapes.items) |shape| {
            freeShapes(allocator, shape.items);
            freeAnimatedMulti(allocator, shape.size);
            freeAnimatedMulti(allocator, shape.position);
            freeAnimatedValue(allocator, shape.roundness);
            freeAnimatedMulti(allocator, shape.color);
            freeAnimatedValue(allocator, shape.opacity);
            freeAnimatedValue(allocator, shape.stroke_width);
            freeTransform(allocator, shape.transform);
            if (shape.name) |n| allocator.free(n);
        }
        shapes.deinit(allocator);
    }

    for (arr.items) |item| {
        if (item != .object) return ParseError.InvalidJson;
        const shape = try parseSingleShape(allocator, item.object);
        shapes.append(allocator, shape) catch return ParseError.OutOfMemory;
    }

    return shapes.toOwnedSlice(allocator) catch return ParseError.OutOfMemory;
}

/// Parse a single shape object.
fn parseSingleShape(allocator: Allocator, obj: std.json.ObjectMap) ParseError!Shape {
    const ty_str = if (obj.get("ty")) |ty_val| switch (ty_val) {
        .string => |s| s,
        else => return ParseError.InvalidJson,
    } else return ParseError.MissingRequiredField;

    const ty = shapeTypeFromStr(ty_str);

    const shape_name: ?[]const u8 = if (obj.get("nm")) |nm| switch (nm) {
        .string => |s| allocator.dupe(u8, s) catch return ParseError.OutOfMemory,
        else => null,
    } else null;
    errdefer if (shape_name) |n| allocator.free(n);

    // Group: parse sub-items from "it"
    var items: []const Shape = &.{};
    if (ty == .group) {
        if (obj.get("it")) |it_val| {
            items = try parseShapes(allocator, it_val);
        }
    }
    errdefer freeShapes(allocator, items);

    // Rectangle / Ellipse fields
    const size = if (obj.get("s")) |s| try parseAnimatedMulti(allocator, s) else null;
    errdefer freeAnimatedMulti(allocator, size);

    const position = if (obj.get("p")) |p| try parseAnimatedMulti(allocator, p) else null;
    errdefer freeAnimatedMulti(allocator, position);

    const roundness = if (obj.get("r")) |r| try parseAnimatedScalar(allocator, r) else null;
    errdefer freeAnimatedValue(allocator, roundness);

    // Fill / Stroke fields
    const color = if (obj.get("c")) |c| try parseAnimatedMulti(allocator, c) else null;
    errdefer freeAnimatedMulti(allocator, color);

    const opacity = if (obj.get("o")) |o| try parseAnimatedScalar(allocator, o) else null;
    errdefer freeAnimatedValue(allocator, opacity);

    const stroke_width = if (obj.get("w")) |w| try parseAnimatedScalar(allocator, w) else null;
    errdefer freeAnimatedValue(allocator, stroke_width);

    // Shape-level transform (inside group's "it" array, ty="tr")
    var transform: ?Transform = null;
    if (ty == .transform) {
        transform = try parseTransformFromShapeFields(allocator, obj);
    }
    errdefer freeTransform(allocator, transform);

    return Shape{
        .ty = ty,
        .name = shape_name,
        .items = items,
        .size = size,
        .position = position,
        .roundness = roundness,
        .color = color,
        .opacity = opacity,
        .stroke_width = stroke_width,
        .transform = transform,
    };
}

/// Parse a transform directly from a shape object's fields (for ty="tr").
fn parseTransformFromShapeFields(allocator: Allocator, obj: std.json.ObjectMap) ParseError!Transform {
    const anchor = if (obj.get("a")) |a| try parseAnimatedMulti(allocator, a) else null;
    errdefer freeAnimatedMulti(allocator, anchor);

    const position = if (obj.get("p")) |p| try parseAnimatedMulti(allocator, p) else null;
    errdefer freeAnimatedMulti(allocator, position);

    const scale = if (obj.get("s")) |s| try parseAnimatedMulti(allocator, s) else null;
    errdefer freeAnimatedMulti(allocator, scale);

    const rotation = if (obj.get("r")) |r| try parseAnimatedScalar(allocator, r) else null;
    errdefer freeAnimatedValue(allocator, rotation);

    const opacity_val = if (obj.get("o")) |o| try parseAnimatedScalar(allocator, o) else null;
    errdefer freeAnimatedValue(allocator, opacity_val);

    return Transform{
        .anchor = anchor,
        .position = position,
        .scale = scale,
        .rotation = rotation,
        .opacity = opacity_val,
    };
}

/// Map a Lottie shape type string to our enum.
fn shapeTypeFromStr(s: []const u8) ShapeType {
    if (std.mem.eql(u8, s, "gr")) return .group;
    if (std.mem.eql(u8, s, "rc")) return .rectangle;
    if (std.mem.eql(u8, s, "el")) return .ellipse;
    if (std.mem.eql(u8, s, "sh")) return .path;
    if (std.mem.eql(u8, s, "fl")) return .fill;
    if (std.mem.eql(u8, s, "st")) return .stroke;
    if (std.mem.eql(u8, s, "tr")) return .transform;
    if (std.mem.eql(u8, s, "gf")) return .gradient_fill;
    if (std.mem.eql(u8, s, "gs")) return .gradient_stroke;
    if (std.mem.eql(u8, s, "mm")) return .merge;
    if (std.mem.eql(u8, s, "tm")) return .trim;
    if (std.mem.eql(u8, s, "rd")) return .round_corners;
    if (std.mem.eql(u8, s, "rp")) return .repeater;
    if (std.mem.eql(u8, s, "sr")) return .star;
    return .unknown;
}

// ---------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------

/// Extract a float from a JSON number value (integer or float).
fn jsonFloat(val: std.json.Value) ?f64 {
    return switch (val) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

/// Extract an integer from a JSON integer value.
fn jsonInt(val: std.json.Value) ?i64 {
    return switch (val) {
        .integer => |i| i,
        else => null,
    };
}

/// Extract an unsigned integer from a JSON integer value.
fn jsonUint(comptime T: type, val: std.json.Value) ?T {
    return switch (val) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        else => null,
    };
}

/// Parse a JSON array of numbers into an f64 slice.
fn jsonFloatArray(allocator: Allocator, arr: std.json.Array) ParseError![]f64 {
    const values = allocator.alloc(f64, arr.items.len) catch return ParseError.OutOfMemory;
    for (arr.items, 0..) |item, i| {
        values[i] = jsonFloat(item) orelse 0;
    }
    return values;
}

// ---------------------------------------------------------------
// WASM exports
// ---------------------------------------------------------------

/// Returns a pointer to the version string (for WASM hosts).
export fn lottie_version() [*]const u8 {
    return version.ptr;
}

/// Returns the length of the version string.
export fn lottie_version_len() u32 {
    return version.len;
}

// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

const testing = std.testing;

test "version is semver" {
    var dot_count: usize = 0;
    for (version) |c| {
        if (c == '.') dot_count += 1;
    }
    try testing.expectEqual(@as(usize, 2), dot_count);
}

test "parse valid minimal lottie json" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqualStrings("5.7.1", anim.version_str);
    try testing.expectEqual(@as(f64, 30.0), anim.frame_rate);
    try testing.expectEqual(@as(f64, 0.0), anim.in_point);
    try testing.expectEqual(@as(f64, 60.0), anim.out_point);
    try testing.expectEqual(@as(u32, 512), anim.width);
    try testing.expectEqual(@as(u32, 512), anim.height);
    try testing.expectEqual(@as(usize, 0), anim.layers.len);
}

test "parse rejects invalid json" {
    const result = parse(testing.allocator, "not json at all");
    try testing.expectError(ParseError.InvalidJson, result);
}

test "parse rejects json missing required fields" {
    const json =
        \\{"v":"5.7.1"}
    ;
    const result = parse(testing.allocator, json);
    try testing.expectError(ParseError.MissingRequiredField, result);
}

test "parse animation with name" {
    const json =
        \\{"v":"5.7.1","fr":24,"ip":0,"op":48,"w":100,"h":100,"nm":"my_anim","layers":[]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqualStrings("my_anim", anim.name.?);
}

test "parse animation with layers" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[
        \\  {"ty":4,"nm":"Shape Layer","ind":1,"ip":0,"op":60},
        \\  {"ty":3,"nm":"Null","ind":2,"parent":1,"ip":0,"op":60}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(@as(usize, 2), anim.layers.len);

    const l0 = anim.layers[0];
    try testing.expectEqual(LayerType.shape, l0.ty);
    try testing.expectEqualStrings("Shape Layer", l0.name.?);
    try testing.expectEqual(@as(i64, 1), l0.index.?);
    try testing.expect(l0.parent == null);
    try testing.expectEqual(@as(f64, 0.0), l0.in_point);
    try testing.expectEqual(@as(f64, 60.0), l0.out_point);

    const l1 = anim.layers[1];
    try testing.expectEqual(LayerType.null_object, l1.ty);
    try testing.expectEqualStrings("Null", l1.name.?);
    try testing.expectEqual(@as(i64, 2), l1.index.?);
    try testing.expectEqual(@as(i64, 1), l1.parent.?);
}

test "animation duration calculation" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":90,"w":100,"h":100,"layers":[]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(@as(f64, 3.0), anim.duration());
}

test "parse layer types" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":0,"ip":0,"op":60},
        \\  {"ty":1,"ip":0,"op":60},
        \\  {"ty":2,"ip":0,"op":60},
        \\  {"ty":4,"ip":0,"op":60},
        \\  {"ty":5,"ip":0,"op":60}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(LayerType.precomp, anim.layers[0].ty);
    try testing.expectEqual(LayerType.solid, anim.layers[1].ty);
    try testing.expectEqual(LayerType.image, anim.layers[2].ty);
    try testing.expectEqual(LayerType.shape, anim.layers[3].ty);
    try testing.expectEqual(LayerType.text, anim.layers[4].ty);
}

test "parse rejects layer missing ty" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"nm":"no type"}
        \\]}
    ;
    const result = parse(testing.allocator, json);
    try testing.expectError(ParseError.MissingRequiredField, result);
}

test "parse animation without layers field" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(@as(usize, 0), anim.layers.len);
}

// -- Transform tests --

test "parse layer with static transform" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "a":{"a":0,"k":[256,256,0]},
        \\    "p":{"a":0,"k":[256,256,0]},
        \\    "s":{"a":0,"k":[100,100,100]},
        \\    "r":{"a":0,"k":0},
        \\    "o":{"a":0,"k":100}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const layer = anim.layers[0];
    try testing.expect(layer.transform != null);
    const tr = layer.transform.?;

    // Anchor point
    try testing.expect(tr.anchor != null);
    switch (tr.anchor.?) {
        .static => |vals| {
            try testing.expectEqual(@as(usize, 3), vals.len);
            try testing.expectEqual(@as(f64, 256.0), vals[0]);
            try testing.expectEqual(@as(f64, 256.0), vals[1]);
        },
        .keyframed => unreachable,
    }

    // Position
    try testing.expect(tr.position != null);
    switch (tr.position.?) {
        .static => |vals| {
            try testing.expectEqual(@as(f64, 256.0), vals[0]);
        },
        .keyframed => unreachable,
    }

    // Scale
    try testing.expect(tr.scale != null);
    switch (tr.scale.?) {
        .static => |vals| {
            try testing.expectEqual(@as(f64, 100.0), vals[0]);
        },
        .keyframed => unreachable,
    }

    // Rotation
    try testing.expect(tr.rotation != null);
    switch (tr.rotation.?) {
        .static => |v| try testing.expectEqual(@as(f64, 0.0), v),
        .keyframed => unreachable,
    }

    // Opacity
    try testing.expect(tr.opacity != null);
    switch (tr.opacity.?) {
        .static => |v| try testing.expectEqual(@as(f64, 100.0), v),
        .keyframed => unreachable,
    }
}

test "parse animated scalar property with keyframes" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "o":{"a":1,"k":[
        \\      {"t":0,"s":[100],"o":{"x":[0.33],"y":[0]},"i":{"x":[0.67],"y":[1]}},
        \\      {"t":30,"s":[0]},
        \\      {"t":60,"s":[100]}
        \\    ]}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const tr = anim.layers[0].transform.?;
    try testing.expect(tr.opacity != null);

    switch (tr.opacity.?) {
        .keyframed => |kfs| {
            try testing.expectEqual(@as(usize, 3), kfs.len);

            // First keyframe
            try testing.expectEqual(@as(f64, 0.0), kfs[0].time);
            try testing.expectEqual(@as(f64, 100.0), kfs[0].value);
            try testing.expect(kfs[0].ease_out != null);
            try testing.expectApproxEqAbs(@as(f64, 0.33), kfs[0].ease_out.?[0], 0.01);
            try testing.expectEqual(@as(f64, 0.0), kfs[0].ease_out.?[1]);
            try testing.expect(kfs[0].ease_in != null);
            try testing.expectApproxEqAbs(@as(f64, 0.67), kfs[0].ease_in.?[0], 0.01);

            // Second keyframe
            try testing.expectEqual(@as(f64, 30.0), kfs[1].time);
            try testing.expectEqual(@as(f64, 0.0), kfs[1].value);

            // Third keyframe
            try testing.expectEqual(@as(f64, 60.0), kfs[2].time);
            try testing.expectEqual(@as(f64, 100.0), kfs[2].value);
        },
        .static => unreachable,
    }
}

test "parse animated multi-dimensional property with keyframes" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "p":{"a":1,"k":[
        \\      {"t":0,"s":[0,0,0]},
        \\      {"t":30,"s":[256,256,0]}
        \\    ]}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const tr = anim.layers[0].transform.?;
    try testing.expect(tr.position != null);

    switch (tr.position.?) {
        .keyframed => |kfs| {
            try testing.expectEqual(@as(usize, 2), kfs.len);

            try testing.expectEqual(@as(f64, 0.0), kfs[0].time);
            try testing.expectEqual(@as(usize, 3), kfs[0].values.len);
            try testing.expectEqual(@as(f64, 0.0), kfs[0].values[0]);

            try testing.expectEqual(@as(f64, 30.0), kfs[1].time);
            try testing.expectEqual(@as(f64, 256.0), kfs[1].values[0]);
            try testing.expectEqual(@as(f64, 256.0), kfs[1].values[1]);
        },
        .static => unreachable,
    }
}

// -- Shape tests --

test "parse shape layer with rectangle" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"rc","nm":"Rect","s":{"a":0,"k":[200,100]},"p":{"a":0,"k":[50,50]},"r":{"a":0,"k":10}}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(@as(usize, 1), anim.layers[0].shapes.len);
    const rect = anim.layers[0].shapes[0];

    try testing.expectEqual(ShapeType.rectangle, rect.ty);
    try testing.expectEqualStrings("Rect", rect.name.?);

    // Size
    try testing.expect(rect.size != null);
    switch (rect.size.?) {
        .static => |vals| {
            try testing.expectEqual(@as(usize, 2), vals.len);
            try testing.expectEqual(@as(f64, 200.0), vals[0]);
            try testing.expectEqual(@as(f64, 100.0), vals[1]);
        },
        .keyframed => unreachable,
    }

    // Position
    try testing.expect(rect.position != null);
    switch (rect.position.?) {
        .static => |vals| {
            try testing.expectEqual(@as(f64, 50.0), vals[0]);
        },
        .keyframed => unreachable,
    }

    // Roundness
    try testing.expect(rect.roundness != null);
    switch (rect.roundness.?) {
        .static => |v| try testing.expectEqual(@as(f64, 10.0), v),
        .keyframed => unreachable,
    }
}

test "parse shape layer with ellipse" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"el","nm":"Ellipse","s":{"a":0,"k":[80,80]},"p":{"a":0,"k":[50,50]}}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const el = anim.layers[0].shapes[0];
    try testing.expectEqual(ShapeType.ellipse, el.ty);
    try testing.expectEqualStrings("Ellipse", el.name.?);

    switch (el.size.?) {
        .static => |vals| {
            try testing.expectEqual(@as(f64, 80.0), vals[0]);
            try testing.expectEqual(@as(f64, 80.0), vals[1]);
        },
        .keyframed => unreachable,
    }
}

test "parse shape layer with fill" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"fl","nm":"Fill","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const fill = anim.layers[0].shapes[0];
    try testing.expectEqual(ShapeType.fill, fill.ty);

    // Color [r, g, b, a]
    switch (fill.color.?) {
        .static => |vals| {
            try testing.expectEqual(@as(f64, 1.0), vals[0]); // r
            try testing.expectEqual(@as(f64, 0.0), vals[1]); // g
            try testing.expectEqual(@as(f64, 0.0), vals[2]); // b
        },
        .keyframed => unreachable,
    }

    // Opacity
    switch (fill.opacity.?) {
        .static => |v| try testing.expectEqual(@as(f64, 100.0), v),
        .keyframed => unreachable,
    }
}

test "parse shape layer with stroke" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"st","nm":"Stroke","c":{"a":0,"k":[0,0,0,1]},"o":{"a":0,"k":100},"w":{"a":0,"k":2}}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const stroke = anim.layers[0].shapes[0];
    try testing.expectEqual(ShapeType.stroke, stroke.ty);

    // Stroke width
    switch (stroke.stroke_width.?) {
        .static => |v| try testing.expectEqual(@as(f64, 2.0), v),
        .keyframed => unreachable,
    }
}

test "parse shape group with nested items" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"gr","nm":"Group","it":[
        \\      {"ty":"rc","nm":"Rect","s":{"a":0,"k":[100,100]},"p":{"a":0,"k":[0,0]}},
        \\      {"ty":"fl","nm":"Fill","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}},
        \\      {"ty":"tr","nm":"Transform","a":{"a":0,"k":[0,0]},"p":{"a":0,"k":[50,50]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
        \\    ]}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqual(@as(usize, 1), anim.layers[0].shapes.len);
    const group = anim.layers[0].shapes[0];

    try testing.expectEqual(ShapeType.group, group.ty);
    try testing.expectEqualStrings("Group", group.name.?);
    try testing.expectEqual(@as(usize, 3), group.items.len);

    // Sub-items
    try testing.expectEqual(ShapeType.rectangle, group.items[0].ty);
    try testing.expectEqual(ShapeType.fill, group.items[1].ty);
    try testing.expectEqual(ShapeType.transform, group.items[2].ty);

    // Group transform (last item, ty="tr")
    const tr_shape = group.items[2];
    try testing.expect(tr_shape.transform != null);
    const tr = tr_shape.transform.?;
    try testing.expect(tr.position != null);
    switch (tr.position.?) {
        .static => |vals| {
            try testing.expectEqual(@as(f64, 50.0), vals[0]);
            try testing.expectEqual(@as(f64, 50.0), vals[1]);
        },
        .keyframed => unreachable,
    }
}

test "parse shape path type" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"sh","nm":"Path 1"}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const path = anim.layers[0].shapes[0];
    try testing.expectEqual(ShapeType.path, path.ty);
    try testing.expectEqualStrings("Path 1", path.name.?);
}

test "parse hold keyframe" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "o":{"a":1,"k":[
        \\      {"t":0,"s":[100],"h":1},
        \\      {"t":30,"s":[0]}
        \\    ]}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const tr = anim.layers[0].transform.?;
    switch (tr.opacity.?) {
        .keyframed => |kfs| {
            try testing.expect(kfs[0].hold);
            try testing.expect(!kfs[1].hold);
        },
        .static => unreachable,
    }
}

test "shapeTypeFromStr maps all known types" {
    try testing.expectEqual(ShapeType.group, shapeTypeFromStr("gr"));
    try testing.expectEqual(ShapeType.rectangle, shapeTypeFromStr("rc"));
    try testing.expectEqual(ShapeType.ellipse, shapeTypeFromStr("el"));
    try testing.expectEqual(ShapeType.path, shapeTypeFromStr("sh"));
    try testing.expectEqual(ShapeType.fill, shapeTypeFromStr("fl"));
    try testing.expectEqual(ShapeType.stroke, shapeTypeFromStr("st"));
    try testing.expectEqual(ShapeType.transform, shapeTypeFromStr("tr"));
    try testing.expectEqual(ShapeType.gradient_fill, shapeTypeFromStr("gf"));
    try testing.expectEqual(ShapeType.gradient_stroke, shapeTypeFromStr("gs"));
    try testing.expectEqual(ShapeType.merge, shapeTypeFromStr("mm"));
    try testing.expectEqual(ShapeType.trim, shapeTypeFromStr("tm"));
    try testing.expectEqual(ShapeType.round_corners, shapeTypeFromStr("rd"));
    try testing.expectEqual(ShapeType.repeater, shapeTypeFromStr("rp"));
    try testing.expectEqual(ShapeType.star, shapeTypeFromStr("sr"));
    try testing.expectEqual(ShapeType.unknown, shapeTypeFromStr("??"));
}

test "parse rejects shape missing ty" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"nm":"no type"}
        \\  ]}
        \\]}
    ;
    const result = parse(testing.allocator, json);
    try testing.expectError(ParseError.MissingRequiredField, result);
}
