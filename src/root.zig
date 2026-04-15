const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Allocator = std.mem.Allocator;

/// Semantic version of the zig-lottie library, read from VERSION at build time.
pub const version = build_options.version;

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
// Validation
// ---------------------------------------------------------------

/// Severity of a validation issue.
pub const Severity = enum {
    @"error",
    warning,
};

/// A single validation issue found in a parsed animation.
pub const ValidationIssue = struct {
    severity: Severity,
    message: []const u8,
};

/// Validate a parsed animation for semantic correctness.
/// Returns a list of issues (errors and warnings). An animation is
/// considered valid when the list contains zero error-severity issues.
/// Caller owns the returned slice and each message string.
pub fn validate(allocator: Allocator, anim: *const Animation) ![]ValidationIssue {
    var issues: std.ArrayList(ValidationIssue) = .empty;
    errdefer {
        for (issues.items) |issue| allocator.free(issue.message);
        issues.deinit(allocator);
    }

    // -- Animation-level errors --

    if (anim.frame_rate <= 0) {
        try addIssue(allocator, &issues, .@"error", "frame_rate must be positive, got {d}", .{anim.frame_rate});
    }

    if (anim.out_point <= anim.in_point) {
        try addIssue(allocator, &issues, .@"error", "out_point ({d}) must be greater than in_point ({d})", .{ anim.out_point, anim.in_point });
    }

    if (anim.width == 0) {
        try addIssue(allocator, &issues, .@"error", "width must be positive", .{});
    }

    if (anim.height == 0) {
        try addIssue(allocator, &issues, .@"error", "height must be positive", .{});
    }

    // Version check: Lottie spec versions 4.x and 5.x are well-known.
    // Versions below 4.0.0 are considered unsupported.
    if (!isVersionSupported(anim.version_str)) {
        try addIssue(allocator, &issues, .@"error", "unsupported Lottie version \"{s}\" (expected 4.x or 5.x)", .{anim.version_str});
    }

    // -- Layer-level checks --

    if (anim.layers.len == 0) {
        try addIssue(allocator, &issues, .warning, "animation has no layers", .{});
    }

    // Collect layer indices for parent ref and duplicate checks.
    for (anim.layers, 0..) |layer, li| {
        // Layer timing
        if (layer.out_point < layer.in_point) {
            try addIssue(allocator, &issues, .warning, "layer {d}: out_point ({d}) is before in_point ({d})", .{ li, layer.out_point, layer.in_point });
        }

        // Dangling parent reference
        if (layer.parent) |parent_idx| {
            var found = false;
            for (anim.layers) |other| {
                if (other.index) |idx| {
                    if (idx == parent_idx) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                try addIssue(allocator, &issues, .@"error", "layer {d}: parent index {d} does not match any layer", .{ li, parent_idx });
            }
        }
    }

    // Duplicate layer indices
    for (anim.layers, 0..) |layer, i| {
        const idx = layer.index orelse continue;
        for (anim.layers[i + 1 ..], 0..) |other, j_off| {
            const other_idx = other.index orelse continue;
            if (idx == other_idx) {
                try addIssue(allocator, &issues, .warning, "duplicate layer index {d} (layers {d} and {d})", .{ idx, i, i + 1 + j_off });
                break; // one warning per pair is enough
            }
        }
    }

    return issues.toOwnedSlice(allocator);
}

fn addIssue(
    allocator: Allocator,
    issues: *std.ArrayList(ValidationIssue),
    severity: Severity,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const message = try std.fmt.allocPrint(allocator, fmt, args);
    issues.append(allocator, .{ .severity = severity, .message = message }) catch |err| {
        allocator.free(message);
        return err;
    };
}

fn isVersionSupported(ver: []const u8) bool {
    if (ver.len == 0) return false;
    const major = ver[0];
    return major == '4' or major == '5';
}

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
    errdefer keyframes.deinit(allocator);

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
        errdefer allocator.free(values);

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

    // Parse fields conditionally by shape type to avoid misinterpreting
    // short field names that mean different things per shape type.
    // e.g. "r" = roundness (rectangle), fill rule (fill), rotation (transform)
    // e.g. "o" = opacity (fill/stroke), but bare integer elsewhere
    // e.g. "s" = size (rect/ellipse), scale (transform), start value (keyframe)

    // Rectangle / Ellipse: size ("s"), position ("p"), roundness ("r")
    const has_geometry = ty == .rectangle or ty == .ellipse;
    const size = if (has_geometry) if (obj.get("s")) |s| try parseAnimatedMulti(allocator, s) else null else null;
    errdefer freeAnimatedMulti(allocator, size);

    const position = if (has_geometry) if (obj.get("p")) |p| try parseAnimatedMulti(allocator, p) else null else null;
    errdefer freeAnimatedMulti(allocator, position);

    const roundness = if (ty == .rectangle) if (obj.get("r")) |r| try parseAnimatedScalar(allocator, r) else null else null;
    errdefer freeAnimatedValue(allocator, roundness);

    // Fill / Stroke: color ("c"), opacity ("o"), stroke width ("w")
    const has_style = ty == .fill or ty == .stroke;
    const color = if (has_style) if (obj.get("c")) |c| try parseAnimatedMulti(allocator, c) else null else null;
    errdefer freeAnimatedMulti(allocator, color);

    const opacity = if (has_style) if (obj.get("o")) |o| try parseAnimatedScalar(allocator, o) else null else null;
    errdefer freeAnimatedValue(allocator, opacity);

    const stroke_width = if (ty == .stroke) if (obj.get("w")) |w| try parseAnimatedScalar(allocator, w) else null else null;
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

const is_wasm = builtin.cpu.arch.isWasm();
const wasm_allocator = if (is_wasm)
    std.heap.wasm_allocator
else
    std.heap.page_allocator;

/// Returns a pointer to the version string (for WASM hosts).
export fn lottie_version() [*]const u8 {
    return version.ptr;
}

/// Returns the length of the version string.
export fn lottie_version_len() u32 {
    return version.len;
}

/// Allocate a buffer in WASM memory (for the host to write JSON into).
export fn lottie_alloc(len: u32) ?[*]u8 {
    const slice = wasm_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

/// Free a buffer previously allocated by lottie_alloc.
export fn lottie_free(ptr: [*]u8, len: u32) void {
    wasm_allocator.free(ptr[0..len]);
}

/// Parse a Lottie JSON buffer already in WASM memory.
/// Returns a pointer to a JSON result string, or null on error.
/// The caller must free the result with lottie_free.
/// Result format: `{ "ok": true, "version": "...", "frame_rate": N, ... }`
export fn lottie_parse(ptr: [*]const u8, len: u32) ?[*]u8 {
    return lottieParseInner(ptr, len) catch return null;
}

fn lottieParseInner(ptr: [*]const u8, len: u32) !?[*]u8 {
    const json_buf = ptr[0..len];
    const anim = parse(wasm_allocator, json_buf) catch return null;
    defer anim.deinit();

    // Build a simple JSON result string using only integer formatting
    // to avoid pulling in the full float-to-decimal machinery (~5KB).
    var aw: std.Io.Writer.Allocating = .init(wasm_allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try writeStr(w, "{\"ok\":true,\"version\":\"");
    try writeStr(w, anim.version_str);
    try writeStr(w, "\",\"frame_rate\":");
    try writeF64(w, anim.frame_rate);
    try writeStr(w, ",\"in_point\":");
    try writeF64(w, anim.in_point);
    try writeStr(w, ",\"out_point\":");
    try writeF64(w, anim.out_point);
    try writeStr(w, ",\"width\":");
    try writeU32(w, anim.width);
    try writeStr(w, ",\"height\":");
    try writeU32(w, anim.height);
    try writeStr(w, ",\"duration\":");
    try writeF64(w, anim.duration());
    try writeStr(w, ",\"layer_count\":");
    try writeUsize(w, anim.layers.len);

    // Add name if present
    if (anim.name) |name| {
        try writeStr(w, ",\"name\":\"");
        try writeStr(w, name);
        try writeStr(w, "\"");
    }

    // Add layers summary
    try writeStr(w, ",\"layers\":[");
    for (anim.layers, 0..) |layer, i| {
        if (i > 0) try writeStr(w, ",");
        try writeStr(w, "{\"ty\":");
        try writeUsize(w, @intFromEnum(layer.ty));
        if (layer.name) |name| {
            try writeStr(w, ",\"name\":\"");
            try writeStr(w, name);
            try writeStr(w, "\"");
        }
        try writeStr(w, ",\"shapes\":");
        try writeUsize(w, layer.shapes.len);
        try writeStr(w, ",\"has_transform\":");
        try writeStr(w, if (layer.transform != null) "true" else "false");
        try writeStr(w, "}");
    }
    try writeStr(w, "]}");

    const slice = try aw.toOwnedSlice();
    return slice.ptr;
}

/// Validate a Lottie JSON buffer already in WASM memory.
/// Returns a pointer to a JSON result string, or null on error.
/// Result format: `{ "valid": true/false, "errors": N, "warnings": N, "issues": [...] }`
export fn lottie_validate(ptr: [*]const u8, len: u32) ?[*]u8 {
    return lottieValidateInner(ptr, len) catch return null;
}

fn lottieValidateInner(ptr: [*]const u8, len: u32) !?[*]u8 {
    const json_buf = ptr[0..len];
    const anim = parse(wasm_allocator, json_buf) catch return null;
    defer anim.deinit();

    const issues = validate(wasm_allocator, &anim) catch return null;
    defer {
        for (issues) |issue| wasm_allocator.free(issue.message);
        wasm_allocator.free(issues);
    }

    var errors: usize = 0;
    var warnings: usize = 0;
    for (issues) |issue| {
        switch (issue.severity) {
            .@"error" => errors += 1,
            .warning => warnings += 1,
        }
    }

    var aw: std.Io.Writer.Allocating = .init(wasm_allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try writeStr(w, "{\"valid\":");
    try writeStr(w, if (errors == 0) "true" else "false");
    try writeStr(w, ",\"errors\":");
    try writeUsize(w, errors);
    try writeStr(w, ",\"warnings\":");
    try writeUsize(w, warnings);
    try writeStr(w, ",\"issues\":[");

    for (issues, 0..) |issue, i| {
        if (i > 0) try writeStr(w, ",");
        try writeStr(w, "{\"severity\":\"");
        try writeStr(w, switch (issue.severity) {
            .@"error" => "error",
            .warning => "warning",
        });
        try writeStr(w, "\",\"message\":\"");
        // Escape any quotes in the message
        for (issue.message) |c| {
            if (c == '"') {
                try w.writeAll("\\\"");
            } else if (c == '\\') {
                try w.writeAll("\\\\");
            } else {
                try w.writeByte(c);
            }
        }
        try writeStr(w, "\"}");
    }

    try writeStr(w, "]}");

    const out = try aw.toOwnedSlice();
    return out.ptr;
}

/// Write a raw string.
fn writeStr(w: anytype, s: []const u8) !void {
    try w.writeAll(s);
}

/// Write a u32 as decimal without pulling in std.fmt.formatFloat.
fn writeU32(w: anytype, v: u32) !void {
    var buf: [10]u8 = undefined;
    var i: usize = buf.len;
    var n = v;
    if (n == 0) {
        try w.writeByte('0');
        return;
    }
    while (n > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
    try w.writeAll(buf[i..]);
}

/// Write a usize as decimal.
fn writeUsize(w: anytype, v: usize) !void {
    var buf: [20]u8 = undefined;
    var i: usize = buf.len;
    var n = v;
    if (n == 0) {
        try w.writeByte('0');
        return;
    }
    while (n > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
    try w.writeAll(buf[i..]);
}

/// Write an f64 as a fixed-point number with up to 4 decimal places.
/// Avoids std.fmt float formatting (Dragonbox/Ryu tables).
fn writeF64(w: anytype, v: f64) !void {
    const neg = v < 0;
    const abs = if (neg) -v else v;
    if (neg) try w.writeByte('-');

    const int_part: u64 = @intFromFloat(abs);
    const frac = abs - @as(f64, @floatFromInt(int_part));
    // Scale to 4 decimal places
    const frac_scaled: u64 = @intFromFloat(frac * 10000 + 0.5);

    // Write integer part
    var buf: [20]u8 = undefined;
    var i: usize = buf.len;
    var n = int_part;
    if (n == 0) {
        try w.writeByte('0');
    } else {
        while (n > 0) {
            i -= 1;
            buf[i] = @intCast('0' + (n % 10));
            n /= 10;
        }
        try w.writeAll(buf[i..]);
    }

    // Write fractional part (trimming trailing zeros)
    if (frac_scaled > 0) {
        var digits: [4]u8 = undefined;
        var f = frac_scaled;
        var di: usize = 4;
        while (di > 0) {
            di -= 1;
            digits[di] = @intCast('0' + (f % 10));
            f /= 10;
        }
        // Trim trailing zeros
        var last: usize = 4;
        while (last > 0 and digits[last - 1] == '0') last -= 1;
        if (last > 0) {
            try w.writeByte('.');
            try w.writeAll(digits[0..last]);
        }
    }
}

/// Get the length of the last parse result (convenience for JS).
/// This is determined by the JS side reading until null or tracking length.
export fn lottie_result_len(ptr: [*]const u8) u32 {
    var i: u32 = 0;
    while (i < 1024 * 1024) : (i += 1) {
        if (ptr[i] == 0) return i;
        // Look for the closing brace of the JSON
    }
    // Scan for end of JSON by finding last '}'
    return i;
}

/// Compile a single frame of a Lottie animation.
/// Takes the Lottie JSON buffer and a frame number.
/// Returns a pointer to a JSON result string with all resolved values, or null on error.
/// The caller must free the result with lottie_free.
export fn lottie_compile_frame(ptr: [*]const u8, len: u32, frame_num: f64) ?[*]u8 {
    return lottieCompileFrameInner(ptr, len, frame_num) catch return null;
}

fn lottieCompileFrameInner(ptr: [*]const u8, len: u32, frame_num: f64) !?[*]u8 {
    const json_buf = ptr[0..len];
    const anim = parse(wasm_allocator, json_buf) catch return null;
    defer anim.deinit();

    const frame = compileFrame(wasm_allocator, &anim, frame_num) catch return null;
    defer frame.deinit();

    var aw: std.Io.Writer.Allocating = .init(wasm_allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try writeStr(w, "{\"frame\":");
    try writeF64(w, frame.frame);
    try writeStr(w, ",\"layers\":[");

    for (frame.layers, 0..) |layer, li| {
        if (li > 0) try writeStr(w, ",");
        try writeResolvedLayer(w, layer);
    }

    try writeStr(w, "]}");

    const slice = try aw.toOwnedSlice();
    return slice.ptr;
}

/// Compile all frames of a Lottie animation.
/// Returns a pointer to a JSON result string with metadata and all frames, or null on error.
/// The caller must free the result with lottie_free.
export fn lottie_compile(ptr: [*]const u8, len: u32) ?[*]u8 {
    return lottieCompileInner(ptr, len) catch return null;
}

fn lottieCompileInner(ptr: [*]const u8, len: u32) !?[*]u8 {
    const json_buf = ptr[0..len];
    const anim = parse(wasm_allocator, json_buf) catch return null;
    defer anim.deinit();

    const compiled = compile(wasm_allocator, &anim) catch return null;
    defer compiled.deinit();

    var aw: std.Io.Writer.Allocating = .init(wasm_allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try writeStr(w, "{\"frame_rate\":");
    try writeF64(w, compiled.frame_rate);
    try writeStr(w, ",\"width\":");
    try writeU32(w, compiled.width);
    try writeStr(w, ",\"height\":");
    try writeU32(w, compiled.height);
    try writeStr(w, ",\"frame_count\":");
    try writeUsize(w, compiled.frames.len);
    try writeStr(w, ",\"frames\":[");

    for (compiled.frames, 0..) |frame, fi| {
        if (fi > 0) try writeStr(w, ",");
        try writeStr(w, "{\"frame\":");
        try writeF64(w, frame.frame);
        try writeStr(w, ",\"layers\":[");

        for (frame.layers, 0..) |layer, li| {
            if (li > 0) try writeStr(w, ",");
            try writeResolvedLayer(w, layer);
        }

        try writeStr(w, "]}");
    }

    try writeStr(w, "]}");

    const slice = try aw.toOwnedSlice();
    return slice.ptr;
}

/// Write a ResolvedLayer as JSON.
fn writeResolvedLayer(w: anytype, layer: ResolvedLayer) !void {
    try writeStr(w, "{\"ty\":");
    try writeUsize(w, @intFromEnum(layer.ty));
    try writeStr(w, ",\"visible\":");
    try writeStr(w, if (layer.visible) "true" else "false");

    if (layer.name) |name| {
        try writeStr(w, ",\"name\":\"");
        try writeJsonEscaped(w, name);
        try writeStr(w, "\"");
    }

    if (layer.index) |idx| {
        try writeStr(w, ",\"index\":");
        try writeI64(w, idx);
    }

    if (layer.parent) |p| {
        try writeStr(w, ",\"parent\":");
        try writeI64(w, p);
    }

    try writeStr(w, ",\"in_point\":");
    try writeF64(w, layer.in_point);
    try writeStr(w, ",\"out_point\":");
    try writeF64(w, layer.out_point);

    if (layer.transform) |tr| {
        try writeStr(w, ",\"transform\":");
        try writeResolvedTransformJson(w, tr);
    }

    try writeStr(w, ",\"shapes\":[");
    for (layer.shapes, 0..) |shape, si| {
        if (si > 0) try writeStr(w, ",");
        try writeResolvedShapeJson(w, shape);
    }
    try writeStr(w, "]}");
}

/// Write a ResolvedTransform as JSON.
fn writeResolvedTransformJson(w: anytype, tr: ResolvedTransform) !void {
    try writeStr(w, "{\"anchor\":");
    try writeF64Array3(w, tr.anchor);
    try writeStr(w, ",\"position\":");
    try writeF64Array3(w, tr.position);
    try writeStr(w, ",\"scale\":");
    try writeF64Array3(w, tr.scale);
    try writeStr(w, ",\"rotation\":");
    try writeF64(w, tr.rotation);
    try writeStr(w, ",\"opacity\":");
    try writeF64(w, tr.opacity);
    try writeStr(w, "}");
}

/// Write a ResolvedShape as JSON.
fn writeResolvedShapeJson(w: anytype, shape: ResolvedShape) !void {
    try writeStr(w, "{\"ty\":\"");
    try writeStr(w, shapeTypeToStr(shape.ty));
    try writeStr(w, "\"");

    if (shape.name) |name| {
        try writeStr(w, ",\"name\":\"");
        try writeJsonEscaped(w, name);
        try writeStr(w, "\"");
    }

    if (shape.size) |sz| {
        try writeStr(w, ",\"size\":");
        try writeF64Array2(w, sz);
    }

    if (shape.position) |pos| {
        try writeStr(w, ",\"position\":");
        try writeF64Array2(w, pos);
    }

    if (shape.roundness) |r| {
        try writeStr(w, ",\"roundness\":");
        try writeF64(w, r);
    }

    if (shape.color) |c| {
        try writeStr(w, ",\"color\":");
        try writeF64Array4(w, c);
    }

    if (shape.opacity) |o| {
        try writeStr(w, ",\"opacity\":");
        try writeF64(w, o);
    }

    if (shape.stroke_width) |sw| {
        try writeStr(w, ",\"stroke_width\":");
        try writeF64(w, sw);
    }

    if (shape.transform) |tr| {
        try writeStr(w, ",\"transform\":");
        try writeResolvedTransformJson(w, tr);
    }

    if (shape.items.len > 0) {
        try writeStr(w, ",\"items\":[");
        for (shape.items, 0..) |item, i| {
            if (i > 0) try writeStr(w, ",");
            try writeResolvedShapeJson(w, item);
        }
        try writeStr(w, "]");
    }

    try writeStr(w, "}");
}

/// Map ShapeType back to its Lottie string code.
fn shapeTypeToStr(ty: ShapeType) []const u8 {
    return switch (ty) {
        .group => "gr",
        .rectangle => "rc",
        .ellipse => "el",
        .path => "sh",
        .fill => "fl",
        .stroke => "st",
        .transform => "tr",
        .gradient_fill => "gf",
        .gradient_stroke => "gs",
        .merge => "mm",
        .trim => "tm",
        .round_corners => "rd",
        .repeater => "rp",
        .star => "sr",
        .unknown => "??",
    };
}

/// Write a JSON-escaped string (handles quotes and backslashes).
fn writeJsonEscaped(w: anytype, s: []const u8) !void {
    for (s) |c| {
        if (c == '"') {
            try w.writeAll("\\\"");
        } else if (c == '\\') {
            try w.writeAll("\\\\");
        } else {
            try w.writeByte(c);
        }
    }
}

/// Write an i64 as decimal.
fn writeI64(w: anytype, v: i64) !void {
    if (v < 0) {
        try w.writeByte('-');
        // Handle MIN_INT edge case
        if (v == std.math.minInt(i64)) {
            try w.writeAll("9223372036854775808");
            return;
        }
        var buf: [20]u8 = undefined;
        var i: usize = buf.len;
        var n: u64 = @intCast(-v);
        while (n > 0) {
            i -= 1;
            buf[i] = @intCast('0' + (n % 10));
            n /= 10;
        }
        try w.writeAll(buf[i..]);
    } else {
        var buf: [20]u8 = undefined;
        var i: usize = buf.len;
        var n: u64 = @intCast(v);
        if (n == 0) {
            try w.writeByte('0');
            return;
        }
        while (n > 0) {
            i -= 1;
            buf[i] = @intCast('0' + (n % 10));
            n /= 10;
        }
        try w.writeAll(buf[i..]);
    }
}

/// Write a [2]f64 as a JSON array.
fn writeF64Array2(w: anytype, arr: [2]f64) !void {
    try w.writeByte('[');
    try writeF64(w, arr[0]);
    try w.writeByte(',');
    try writeF64(w, arr[1]);
    try w.writeByte(']');
}

/// Write a [3]f64 as a JSON array.
fn writeF64Array3(w: anytype, arr: [3]f64) !void {
    try w.writeByte('[');
    try writeF64(w, arr[0]);
    try w.writeByte(',');
    try writeF64(w, arr[1]);
    try w.writeByte(',');
    try writeF64(w, arr[2]);
    try w.writeByte(']');
}

/// Write a [4]f64 as a JSON array.
fn writeF64Array4(w: anytype, arr: [4]f64) !void {
    try w.writeByte('[');
    try writeF64(w, arr[0]);
    try w.writeByte(',');
    try writeF64(w, arr[1]);
    try w.writeByte(',');
    try writeF64(w, arr[2]);
    try w.writeByte(',');
    try writeF64(w, arr[3]);
    try w.writeByte(']');
}

// ---------------------------------------------------------------
// Compiler — keyframe interpolation
// ---------------------------------------------------------------

/// Evaluate a cubic bezier easing curve at parameter `t` (0..1).
///
/// The curve is defined by control points (0,0), (x1,y1), (x2,y2), (1,1).
/// This is the standard CSS cubic-bezier model used by Lottie.
/// Returns the eased progress (y value) for the given linear progress `t`.
pub fn cubicBezierEase(x1: f64, y1: f64, x2: f64, y2: f64, t: f64) f64 {
    // Clamp input to [0, 1]
    if (t <= 0) return 0;
    if (t >= 1) return 1;

    // Newton-Raphson iteration to solve for the bezier parameter `s`
    // such that bezierX(s) = t, then return bezierY(s).
    // Bezier X(s) = 3*(1-s)^2*s*x1 + 3*(1-s)*s^2*x2 + s^3
    // Bezier Y(s) = 3*(1-s)^2*s*y1 + 3*(1-s)*s^2*y2 + s^3

    var s = t; // initial guess
    const iterations = 8;
    for (0..iterations) |_| {
        const s2 = s * s;
        const s3 = s2 * s;
        const one_s = 1.0 - s;
        const one_s2 = one_s * one_s;

        // X(s)
        const x = 3.0 * one_s2 * s * x1 + 3.0 * one_s * s2 * x2 + s3;
        // X'(s) = derivative
        const dx = 3.0 * one_s2 * x1 + 6.0 * one_s * s * (x2 - x1) + 3.0 * s2 * (1.0 - x2);

        if (@abs(dx) < 1e-12) break;
        s -= (x - t) / dx;
        s = std.math.clamp(s, 0.0, 1.0);
    }

    // Evaluate Y(s)
    const s2 = s * s;
    const s3 = s2 * s;
    const one_s = 1.0 - s;
    const one_s2 = one_s * one_s;
    return 3.0 * one_s2 * s * y1 + 3.0 * one_s * s2 * y2 + s3;
}

/// Linearly interpolate between two values.
fn lerp(a: f64, b: f64, t: f64) f64 {
    return a + (b - a) * t;
}

/// Resolve an AnimatedValue at a given frame time.
/// Returns the interpolated scalar value.
pub fn resolveValue(av: AnimatedValue, frame: f64) f64 {
    switch (av) {
        .static => |v| return v,
        .keyframed => |kfs| {
            if (kfs.len == 0) return 0;
            if (kfs.len == 1) return kfs[0].value;

            // Before first keyframe
            if (frame <= kfs[0].time) return kfs[0].value;
            // After last keyframe
            if (frame >= kfs[kfs.len - 1].time) return kfs[kfs.len - 1].value;

            // Find bracketing keyframes
            for (kfs[0 .. kfs.len - 1], 0..) |kf, i| {
                const next = kfs[i + 1];
                if (frame >= kf.time and frame < next.time) {
                    // Hold keyframe: no interpolation
                    if (kf.hold) return kf.value;

                    // Normalized linear progress
                    const duration = next.time - kf.time;
                    if (duration <= 0) return kf.value;
                    const t = (frame - kf.time) / duration;

                    // Apply easing if present
                    const eased = if (kf.ease_out != null and next.ease_in != null)
                        cubicBezierEase(
                            kf.ease_out.?[0],
                            kf.ease_out.?[1],
                            next.ease_in.?[0],
                            next.ease_in.?[1],
                            t,
                        )
                    else
                        t;

                    return lerp(kf.value, next.value, eased);
                }
            }

            return kfs[kfs.len - 1].value;
        },
    }
}

/// Resolve an AnimatedMulti at a given frame time.
/// Returns a newly allocated slice of interpolated values.
/// Caller owns the returned slice.
pub fn resolveMulti(allocator: Allocator, am: AnimatedMulti, frame: f64) ![]f64 {
    switch (am) {
        .static => |vals| {
            const result = try allocator.alloc(f64, vals.len);
            @memcpy(result, vals);
            return result;
        },
        .keyframed => |kfs| {
            if (kfs.len == 0) return try allocator.alloc(f64, 0);

            // Determine dimensionality from first keyframe
            const dims = kfs[0].values.len;
            const result = try allocator.alloc(f64, dims);

            if (kfs.len == 1) {
                for (0..dims) |d| {
                    result[d] = if (d < kfs[0].values.len) kfs[0].values[d] else 0;
                }
                return result;
            }

            // Before first keyframe
            if (frame <= kfs[0].time) {
                for (0..dims) |d| {
                    result[d] = if (d < kfs[0].values.len) kfs[0].values[d] else 0;
                }
                return result;
            }

            // After last keyframe
            if (frame >= kfs[kfs.len - 1].time) {
                const last = kfs[kfs.len - 1];
                for (0..dims) |d| {
                    result[d] = if (d < last.values.len) last.values[d] else 0;
                }
                return result;
            }

            // Find bracketing keyframes
            for (kfs[0 .. kfs.len - 1], 0..) |kf, i| {
                const next = kfs[i + 1];
                if (frame >= kf.time and frame < next.time) {
                    if (kf.hold) {
                        for (0..dims) |d| {
                            result[d] = if (d < kf.values.len) kf.values[d] else 0;
                        }
                        return result;
                    }

                    const duration = next.time - kf.time;
                    if (duration <= 0) {
                        for (0..dims) |d| {
                            result[d] = if (d < kf.values.len) kf.values[d] else 0;
                        }
                        return result;
                    }
                    const t = (frame - kf.time) / duration;

                    const eased = if (kf.ease_out != null and next.ease_in != null)
                        cubicBezierEase(
                            kf.ease_out.?[0],
                            kf.ease_out.?[1],
                            next.ease_in.?[0],
                            next.ease_in.?[1],
                            t,
                        )
                    else
                        t;

                    for (0..dims) |d| {
                        const a = if (d < kf.values.len) kf.values[d] else 0;
                        const b = if (d < next.values.len) next.values[d] else 0;
                        result[d] = lerp(a, b, eased);
                    }
                    return result;
                }
            }

            // Fallback: last keyframe
            const last = kfs[kfs.len - 1];
            for (0..dims) |d| {
                result[d] = if (d < last.values.len) last.values[d] else 0;
            }
            return result;
        },
    }
}

/// A fully resolved transform at a specific frame — all values are concrete.
pub const ResolvedTransform = struct {
    anchor: [3]f64,
    position: [3]f64,
    scale: [3]f64,
    rotation: f64,
    opacity: f64,
};

/// Resolve a Transform to concrete values at a given frame time.
/// Caller owns any intermediate allocations (uses stack for small arrays).
pub fn resolveTransform(allocator: Allocator, tr: Transform, frame: f64) !ResolvedTransform {
    var result = ResolvedTransform{
        .anchor = .{ 0, 0, 0 },
        .position = .{ 0, 0, 0 },
        .scale = .{ 100, 100, 100 },
        .rotation = 0,
        .opacity = 100,
    };

    if (tr.anchor) |a| {
        const vals = try resolveMulti(allocator, a, frame);
        defer allocator.free(vals);
        for (0..@min(3, vals.len)) |i| result.anchor[i] = vals[i];
    }

    if (tr.position) |p| {
        const vals = try resolveMulti(allocator, p, frame);
        defer allocator.free(vals);
        for (0..@min(3, vals.len)) |i| result.position[i] = vals[i];
    }

    if (tr.scale) |s| {
        const vals = try resolveMulti(allocator, s, frame);
        defer allocator.free(vals);
        for (0..@min(3, vals.len)) |i| result.scale[i] = vals[i];
    }

    if (tr.rotation) |r| {
        result.rotation = resolveValue(r, frame);
    }

    if (tr.opacity) |o| {
        result.opacity = resolveValue(o, frame);
    }

    return result;
}

/// A resolved shape at a specific frame — animated properties are concrete.
pub const ResolvedShape = struct {
    ty: ShapeType,
    name: ?[]const u8,
    /// Resolved sub-shapes (for groups).
    items: []const ResolvedShape,
    /// Rectangle/ellipse size [w, h].
    size: ?[2]f64,
    /// Rectangle/ellipse position [x, y].
    position: ?[2]f64,
    /// Rectangle corner roundness.
    roundness: ?f64,
    /// Fill/stroke color [r, g, b] or [r, g, b, a].
    color: ?[4]f64,
    /// Fill/stroke opacity (0-100).
    opacity: ?f64,
    /// Stroke width.
    stroke_width: ?f64,
    /// Shape-level transform.
    transform: ?ResolvedTransform,
};

/// Resolve a Shape to concrete values at a given frame.
/// Caller owns the returned ResolvedShape and must call freeResolvedShapes.
pub fn resolveShape(allocator: Allocator, shape: Shape, frame: f64) !ResolvedShape {
    // Resolve sub-items (for groups)
    var items = std.ArrayList(ResolvedShape).empty;
    errdefer freeResolvedShapes(allocator, items.items);
    for (shape.items) |child| {
        const resolved = try resolveShape(allocator, child, frame);
        items.append(allocator, resolved) catch return error.OutOfMemory;
    }
    const owned_items = items.toOwnedSlice(allocator) catch return error.OutOfMemory;
    errdefer {
        freeResolvedShapes(allocator, owned_items);
    }

    // Resolve animated properties
    const size: ?[2]f64 = if (shape.size) |s| blk: {
        const vals = try resolveMulti(allocator, s, frame);
        defer allocator.free(vals);
        break :blk .{ if (vals.len > 0) vals[0] else 0, if (vals.len > 1) vals[1] else 0 };
    } else null;

    const position: ?[2]f64 = if (shape.position) |p| blk: {
        const vals = try resolveMulti(allocator, p, frame);
        defer allocator.free(vals);
        break :blk .{ if (vals.len > 0) vals[0] else 0, if (vals.len > 1) vals[1] else 0 };
    } else null;

    const roundness: ?f64 = if (shape.roundness) |r| resolveValue(r, frame) else null;

    const color: ?[4]f64 = if (shape.color) |c| blk: {
        const vals = try resolveMulti(allocator, c, frame);
        defer allocator.free(vals);
        break :blk .{
            if (vals.len > 0) vals[0] else 0,
            if (vals.len > 1) vals[1] else 0,
            if (vals.len > 2) vals[2] else 0,
            if (vals.len > 3) vals[3] else 1,
        };
    } else null;

    const opacity: ?f64 = if (shape.opacity) |o| resolveValue(o, frame) else null;
    const stroke_width: ?f64 = if (shape.stroke_width) |w| resolveValue(w, frame) else null;

    const transform: ?ResolvedTransform = if (shape.transform) |t|
        try resolveTransform(allocator, t, frame)
    else
        null;

    return ResolvedShape{
        .ty = shape.ty,
        .name = shape.name,
        .items = owned_items,
        .size = size,
        .position = position,
        .roundness = roundness,
        .color = color,
        .opacity = opacity,
        .stroke_width = stroke_width,
        .transform = transform,
    };
}

/// A single resolved layer at a specific frame.
pub const ResolvedLayer = struct {
    ty: LayerType,
    name: ?[]const u8,
    index: ?i64,
    parent: ?i64,
    in_point: f64,
    out_point: f64,
    transform: ?ResolvedTransform,
    shapes: []const ResolvedShape,
    /// Whether this layer is visible at this frame (in_point <= frame < out_point).
    visible: bool,
};

/// A compiled frame: the full animation state at a specific frame time.
pub const CompiledFrame = struct {
    allocator: Allocator,
    frame: f64,
    layers: []const ResolvedLayer,

    pub fn deinit(self: *const CompiledFrame) void {
        for (self.layers) |layer| {
            freeResolvedShapes(self.allocator, layer.shapes);
        }
        self.allocator.free(self.layers);
    }
};

/// Compile (resolve) an animation at a single frame time.
/// Returns a CompiledFrame with all animated values resolved.
/// Caller owns the returned CompiledFrame and must call deinit().
pub fn compileFrame(allocator: Allocator, anim: *const Animation, frame: f64) !CompiledFrame {
    var layers = std.ArrayList(ResolvedLayer).empty;
    errdefer {
        for (layers.items) |layer| {
            freeResolvedShapes(allocator, layer.shapes);
        }
        layers.deinit(allocator);
    }

    for (anim.layers) |layer| {
        const visible = frame >= layer.in_point and frame < layer.out_point;

        const transform: ?ResolvedTransform = if (layer.transform) |t|
            try resolveTransform(allocator, t, frame)
        else
            null;

        // Resolve shapes
        var resolved_shapes = std.ArrayList(ResolvedShape).empty;
        errdefer freeResolvedShapes(allocator, resolved_shapes.items);

        if (visible) {
            for (layer.shapes) |shape| {
                const rs = try resolveShape(allocator, shape, frame);
                resolved_shapes.append(allocator, rs) catch return error.OutOfMemory;
            }
        }
        const owned_shapes = resolved_shapes.toOwnedSlice(allocator) catch return error.OutOfMemory;
        errdefer freeResolvedShapes(allocator, owned_shapes);

        layers.append(allocator, .{
            .ty = layer.ty,
            .name = layer.name,
            .index = layer.index,
            .parent = layer.parent,
            .in_point = layer.in_point,
            .out_point = layer.out_point,
            .transform = transform,
            .shapes = owned_shapes,
            .visible = visible,
        }) catch return error.OutOfMemory;
    }

    return CompiledFrame{
        .allocator = allocator,
        .frame = frame,
        .layers = layers.toOwnedSlice(allocator) catch return error.OutOfMemory,
    };
}

/// A compiled animation: all frames resolved for the full timeline.
pub const CompiledAnimation = struct {
    allocator: Allocator,
    frame_rate: f64,
    width: u32,
    height: u32,
    frames: []const CompiledFrame,

    pub fn deinit(self: *const CompiledAnimation) void {
        for (self.frames) |*frame| {
            frame.deinit();
        }
        self.allocator.free(self.frames);
    }
};

/// Compile an entire animation: resolve every integer frame from in_point to out_point.
/// Returns a CompiledAnimation with all frames resolved.
/// Caller owns the result and must call deinit().
pub fn compile(allocator: Allocator, anim: *const Animation) !CompiledAnimation {
    const start: i64 = @intFromFloat(@floor(anim.in_point));
    const end: i64 = @intFromFloat(@ceil(anim.out_point));
    const frame_count: usize = if (end > start) @intCast(end - start) else 0;

    var frames = try allocator.alloc(CompiledFrame, frame_count);
    var compiled_count: usize = 0;
    errdefer {
        // Free only the frames we've successfully compiled
        for (frames[0..compiled_count]) |*f| {
            f.deinit();
        }
        allocator.free(frames);
    }

    // Initialize all frames to empty so the slice is valid
    for (frames) |*f| {
        f.* = CompiledFrame{
            .allocator = allocator,
            .frame = 0,
            .layers = &.{},
        };
    }

    for (0..frame_count) |i| {
        const frame_time: f64 = @floatFromInt(start + @as(i64, @intCast(i)));
        frames[i] = try compileFrame(allocator, anim, frame_time);
        compiled_count += 1;
    }

    return CompiledAnimation{
        .allocator = allocator,
        .frame_rate = anim.frame_rate,
        .width = anim.width,
        .height = anim.height,
        .frames = frames,
    };
}

/// Free a slice of ResolvedShapes (recursive).
fn freeResolvedShapes(allocator: Allocator, shapes: []const ResolvedShape) void {
    for (shapes) |shape| {
        freeResolvedShapes(allocator, shape.items);
    }
    allocator.free(shapes);
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

// ---------------------------------------------------------------
// Integration tests — complex fixture files
// ---------------------------------------------------------------

fn readFixture(path: []const u8) ![]u8 {
    const io = testing.io;
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var read_buf: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    return try reader.interface.allocRemaining(testing.allocator, .limited(4 * 1024 * 1024));
}

test "fixture: many_layers.json (148KB, 50 layers)" {
    const json = try readFixture("test/fixtures/many_layers.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqualStrings("5.7.1", anim.version_str);
    try testing.expectEqual(@as(u32, 1024), anim.width);
    try testing.expectEqual(@as(u32, 1024), anim.height);
    try testing.expectEqual(@as(f64, 30.0), anim.frame_rate);
    try testing.expectEqual(@as(usize, 50), anim.layers.len);
    try testing.expectEqualStrings("Many Layers", anim.name.?);

    // Every layer should be a shape layer with one group
    for (anim.layers) |layer| {
        try testing.expectEqual(LayerType.shape, layer.ty);
        try testing.expect(layer.name != null);
        try testing.expect(layer.transform != null);
        try testing.expectEqual(@as(usize, 1), layer.shapes.len);
        try testing.expectEqual(ShapeType.group, layer.shapes[0].ty);
        try testing.expect(layer.shapes[0].items.len >= 3);
    }
}

test "fixture: many_keyframes.json (247KB, orbital animation)" {
    const json = try readFixture("test/fixtures/many_keyframes.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqualStrings("5.7.1", anim.version_str);
    try testing.expectEqual(@as(u32, 1024), anim.width);
    try testing.expectEqual(@as(u32, 1024), anim.height);
    try testing.expectEqual(@as(f64, 60.0), anim.frame_rate);
    try testing.expectEqual(@as(usize, 8), anim.layers.len);
    try testing.expectEqualStrings("Many Keyframes", anim.name.?);

    // Every layer should have animated transforms (at least scale and opacity)
    for (anim.layers) |layer| {
        try testing.expect(layer.transform != null);
        const tr = layer.transform.?;

        // Scale should be keyframed on all layers
        try testing.expect(tr.scale != null);
        switch (tr.scale.?) {
            .keyframed => |kfs| try testing.expect(kfs.len >= 10),
            .static => return error.TestUnexpectedResult,
        }

        // Opacity should be keyframed on all layers
        try testing.expect(tr.opacity != null);
        switch (tr.opacity.?) {
            .keyframed => |kfs| try testing.expect(kfs.len >= 10),
            .static => return error.TestUnexpectedResult,
        }
    }

    // Orbiter layers (1-7) should have keyframed position
    for (anim.layers[1..]) |layer| {
        const tr = layer.transform.?;
        try testing.expect(tr.position != null);
        switch (tr.position.?) {
            .keyframed => |kfs| try testing.expect(kfs.len >= 30),
            .static => return error.TestUnexpectedResult,
        }
    }
}

test "fixture: deep_nesting.json (414KB, fractal garden)" {
    const json = try readFixture("test/fixtures/deep_nesting.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqualStrings("5.7.1", anim.version_str);
    try testing.expectEqual(@as(u32, 800), anim.width);
    try testing.expectEqual(@as(u32, 600), anim.height);
    try testing.expectEqual(@as(f64, 30.0), anim.frame_rate);
    try testing.expectEqual(@as(usize, 8), anim.layers.len);
    try testing.expectEqualStrings("Deep Nesting", anim.name.?);

    // Helper: find first group in a shape slice
    const findGroup = struct {
        fn f(shapes: []const Shape) ?Shape {
            for (shapes) |s| {
                if (s.ty == .group) return s;
            }
            return null;
        }
    }.f;

    // Verify 5-level nesting by walking the first tree (Oak)
    const layer0 = anim.layers[0];
    try testing.expect(layer0.shapes.len >= 1);
    const g1 = layer0.shapes[0];
    try testing.expectEqual(ShapeType.group, g1.ty);
    try testing.expect(g1.items.len >= 2); // child branches + transform

    // Level 2: first child branch
    const g2 = findGroup(g1.items) orelse return error.TestUnexpectedResult;
    try testing.expect(g2.items.len >= 3); // trunk + fill + child + transform

    // Level 3
    const g3 = findGroup(g2.items) orelse return error.TestUnexpectedResult;
    try testing.expect(g3.items.len >= 3);

    // Level 4
    const g4 = findGroup(g3.items) orelse return error.TestUnexpectedResult;
    try testing.expect(g4.items.len >= 3);

    // Level 5 (innermost leaf group)
    const g5 = findGroup(g4.items) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(ShapeType.group, g5.ty);
    try testing.expect(g5.items.len >= 3); // ellipse + fill + transform
}

test "fixture: kitchen_sink.json (282KB, clockwork aquarium)" {
    const json = try readFixture("test/fixtures/kitchen_sink.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    try testing.expectEqualStrings("5.12.2", anim.version_str);
    try testing.expectEqual(@as(u32, 1920), anim.width);
    try testing.expectEqual(@as(u32, 1080), anim.height);
    try testing.expectEqual(@as(f64, 60.0), anim.frame_rate);
    try testing.expectEqual(@as(usize, 20), anim.layers.len);
    try testing.expectEqualStrings("Kitchen Sink", anim.name.?);

    // Count layer types
    var null_count: usize = 0;
    var precomp_count: usize = 0;
    var shape_count: usize = 0;
    for (anim.layers) |layer| {
        switch (layer.ty) {
            .null_object => null_count += 1,
            .precomp => precomp_count += 1,
            .shape => shape_count += 1,
            else => {},
        }
    }
    try testing.expectEqual(@as(usize, 3), null_count);
    try testing.expectEqual(@as(usize, 2), precomp_count);
    try testing.expectEqual(@as(usize, 15), shape_count);

    // Verify parent references exist (some layers should have parent set)
    var parented: usize = 0;
    for (anim.layers) |layer| {
        if (layer.parent != null) parented += 1;
    }
    try testing.expect(parented >= 3);

    // Verify we parsed a variety of shape types
    var has_path = false;
    var has_trim = false;
    var has_round_corners = false;
    for (anim.layers) |layer| {
        for (layer.shapes) |shape| {
            if (shape.ty == .group) {
                for (shape.items) |item| {
                    if (item.ty == .path) has_path = true;
                    if (item.ty == .trim) has_trim = true;
                    if (item.ty == .round_corners) has_round_corners = true;
                }
            }
        }
    }
    try testing.expect(has_path);
    try testing.expect(has_trim);
    try testing.expect(has_round_corners);
}

// ---------------------------------------------------------------
// Validation tests
// ---------------------------------------------------------------

fn parseAndValidate(json: []const u8) !struct { anim: Animation, issues: []ValidationIssue } {
    const anim = try parse(testing.allocator, json);
    const issues = try validate(testing.allocator, &anim);
    return .{ .anim = anim, .issues = issues };
}

fn hasIssue(issues: []const ValidationIssue, severity: Severity, needle: []const u8) bool {
    for (issues) |issue| {
        if (issue.severity == severity and std.mem.indexOf(u8, issue.message, needle) != null) return true;
    }
    return false;
}

fn countErrors(issues: []const ValidationIssue) usize {
    var n: usize = 0;
    for (issues) |issue| {
        if (issue.severity == .@"error") n += 1;
    }
    return n;
}

fn countWarnings(issues: []const ValidationIssue) usize {
    var n: usize = 0;
    for (issues) |issue| {
        if (issue.severity == .warning) n += 1;
    }
    return n;
}

fn freeIssues(allocator: Allocator, issues: []ValidationIssue) void {
    for (issues) |issue| allocator.free(issue.message);
    allocator.free(issues);
}

test "validate: valid minimal animation has no errors" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expectEqual(@as(usize, 0), countErrors(result.issues));
}

test "validate: zero frame rate is an error" {
    const json =
        \\{"v":"5.7.1","fr":0,"ip":0,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "frame_rate"));
}

test "validate: negative frame rate is an error" {
    const json =
        \\{"v":"5.7.1","fr":-1,"ip":0,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "frame_rate"));
}

test "validate: out_point <= in_point is an error" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":60,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "out_point"));
}

test "validate: zero width is an error" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":0,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "width"));
}

test "validate: zero height is an error" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":0,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "height"));
}

test "validate: unsupported version is an error" {
    const json =
        \\{"v":"3.0.0","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "version"));
}

test "validate: dangling parent reference is an error" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[
        \\  {"ty":4,"ind":1,"parent":99,"ip":0,"op":60}
        \\]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .@"error", "parent"));
}

test "validate: duplicate layer indices is a warning" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[
        \\  {"ty":4,"ind":1,"ip":0,"op":60},
        \\  {"ty":4,"ind":1,"ip":0,"op":60}
        \\]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .warning, "duplicate"));
}

test "validate: layer out_point before in_point is a warning" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[
        \\  {"ty":4,"ind":1,"ip":30,"op":10}
        \\]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .warning, "out_point"));
}

test "validate: empty animation (no layers) is a warning" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":512,"h":512,"layers":[]}
    ;
    const result = try parseAndValidate(json);
    defer result.anim.deinit();
    defer freeIssues(testing.allocator, result.issues);

    try testing.expect(hasIssue(result.issues, .warning, "no layers"));
}

test "validate: valid fixtures have no errors" {
    const fixtures = [_][]const u8{
        "test/fixtures/many_layers.json",
        "test/fixtures/many_keyframes.json",
        "test/fixtures/deep_nesting.json",
        "test/fixtures/kitchen_sink.json",
    };
    for (fixtures) |path| {
        const json = try readFixture(path);
        defer testing.allocator.free(json);

        const anim = try parse(testing.allocator, json);
        defer anim.deinit();

        const issues = try validate(testing.allocator, &anim);
        defer freeIssues(testing.allocator, issues);

        try testing.expectEqual(@as(usize, 0), countErrors(issues));
    }
}

// ---------------------------------------------------------------
// Compiler tests — cubic bezier easing
// ---------------------------------------------------------------

test "cubicBezierEase: linear (0,0,1,1) returns t" {
    try testing.expectApproxEqAbs(@as(f64, 0.0), cubicBezierEase(0, 0, 1, 1, 0.0), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.25), cubicBezierEase(0, 0, 1, 1, 0.25), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.5), cubicBezierEase(0, 0, 1, 1, 0.5), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.75), cubicBezierEase(0, 0, 1, 1, 0.75), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), cubicBezierEase(0, 0, 1, 1, 1.0), 0.001);
}

test "cubicBezierEase: ease-in-out (0.42,0,0.58,1) is symmetric around 0.5" {
    const mid = cubicBezierEase(0.42, 0, 0.58, 1, 0.5);
    try testing.expectApproxEqAbs(@as(f64, 0.5), mid, 0.01);

    // Ease-in-out: slow start, so at t=0.25 y should be < 0.25
    const q1 = cubicBezierEase(0.42, 0, 0.58, 1, 0.25);
    try testing.expect(q1 < 0.25);

    // Ease-in-out: fast middle, so at t=0.75 y should be > 0.75
    const q3 = cubicBezierEase(0.42, 0, 0.58, 1, 0.75);
    try testing.expect(q3 > 0.75);
}

test "cubicBezierEase: ease (0.25,0.1,0.25,1) CSS standard" {
    // Known CSS ease: starts slow, ends gentle
    const at_half = cubicBezierEase(0.25, 0.1, 0.25, 1, 0.5);
    try testing.expect(at_half > 0.5); // ease overshoots linear at midpoint
}

test "cubicBezierEase: clamps at boundaries" {
    try testing.expectEqual(@as(f64, 0.0), cubicBezierEase(0.42, 0, 0.58, 1, -1.0));
    try testing.expectEqual(@as(f64, 1.0), cubicBezierEase(0.42, 0, 0.58, 1, 2.0));
}

// ---------------------------------------------------------------
// Compiler tests — resolveValue (scalar)
// ---------------------------------------------------------------

test "resolveValue: static returns constant" {
    const av = AnimatedValue{ .static = 42.0 };
    try testing.expectEqual(@as(f64, 42.0), resolveValue(av, 0));
    try testing.expectEqual(@as(f64, 42.0), resolveValue(av, 100));
}

test "resolveValue: single keyframe returns that value" {
    const kfs = [_]Keyframe{.{ .time = 0, .value = 75, .ease_out = null, .ease_in = null, .hold = false }};
    const av = AnimatedValue{ .keyframed = &kfs };
    try testing.expectEqual(@as(f64, 75.0), resolveValue(av, -10));
    try testing.expectEqual(@as(f64, 75.0), resolveValue(av, 0));
    try testing.expectEqual(@as(f64, 75.0), resolveValue(av, 100));
}

test "resolveValue: linear interpolation between two keyframes" {
    const kfs = [_]Keyframe{
        .{ .time = 0, .value = 0, .ease_out = null, .ease_in = null, .hold = false },
        .{ .time = 60, .value = 100, .ease_out = null, .ease_in = null, .hold = false },
    };
    const av = AnimatedValue{ .keyframed = &kfs };

    try testing.expectApproxEqAbs(@as(f64, 0.0), resolveValue(av, 0), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 50.0), resolveValue(av, 30), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 100.0), resolveValue(av, 60), 0.001);
}

test "resolveValue: clamps before first and after last keyframe" {
    const kfs = [_]Keyframe{
        .{ .time = 10, .value = 20, .ease_out = null, .ease_in = null, .hold = false },
        .{ .time = 50, .value = 80, .ease_out = null, .ease_in = null, .hold = false },
    };
    const av = AnimatedValue{ .keyframed = &kfs };

    try testing.expectEqual(@as(f64, 20.0), resolveValue(av, 0));
    try testing.expectEqual(@as(f64, 80.0), resolveValue(av, 100));
}

test "resolveValue: hold keyframe returns left value" {
    const kfs = [_]Keyframe{
        .{ .time = 0, .value = 100, .ease_out = null, .ease_in = null, .hold = true },
        .{ .time = 30, .value = 0, .ease_out = null, .ease_in = null, .hold = false },
    };
    const av = AnimatedValue{ .keyframed = &kfs };

    try testing.expectEqual(@as(f64, 100.0), resolveValue(av, 0));
    try testing.expectEqual(@as(f64, 100.0), resolveValue(av, 15));
    try testing.expectEqual(@as(f64, 100.0), resolveValue(av, 29));
}

test "resolveValue: eased interpolation" {
    const kfs = [_]Keyframe{
        .{ .time = 0, .value = 0, .ease_out = Vec2{ 0.42, 0 }, .ease_in = null, .hold = false },
        .{ .time = 60, .value = 100, .ease_out = null, .ease_in = Vec2{ 0.58, 1 }, .hold = false },
    };
    const av = AnimatedValue{ .keyframed = &kfs };

    const at_half = resolveValue(av, 30);
    // With ease-in-out, at t=0.5 value should be ~50 (symmetric curve)
    try testing.expectApproxEqAbs(@as(f64, 50.0), at_half, 2.0);
}

test "resolveValue: multiple segments" {
    const kfs = [_]Keyframe{
        .{ .time = 0, .value = 0, .ease_out = null, .ease_in = null, .hold = false },
        .{ .time = 30, .value = 100, .ease_out = null, .ease_in = null, .hold = false },
        .{ .time = 60, .value = 50, .ease_out = null, .ease_in = null, .hold = false },
    };
    const av = AnimatedValue{ .keyframed = &kfs };

    try testing.expectApproxEqAbs(@as(f64, 50.0), resolveValue(av, 15), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 100.0), resolveValue(av, 30), 0.001);
    try testing.expectApproxEqAbs(@as(f64, 75.0), resolveValue(av, 45), 0.001);
}

// ---------------------------------------------------------------
// Compiler tests — resolveMulti (multi-dimensional)
// ---------------------------------------------------------------

test "resolveMulti: static returns copy of values" {
    const static_vals = [_]f64{ 100, 200, 0 };
    const am = AnimatedMulti{ .static = &static_vals };

    const result = try resolveMulti(testing.allocator, am, 0);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqual(@as(f64, 100.0), result[0]);
    try testing.expectEqual(@as(f64, 200.0), result[1]);
}

test "resolveMulti: linear interpolation between two keyframes" {
    const vals0 = [_]f64{ 0, 0 };
    const vals1 = [_]f64{ 100, 200 };
    const kfs = [_]MultiKeyframe{
        .{ .time = 0, .values = &vals0, .ease_out = null, .ease_in = null, .hold = false },
        .{ .time = 60, .values = &vals1, .ease_out = null, .ease_in = null, .hold = false },
    };
    const am = AnimatedMulti{ .keyframed = &kfs };

    const result = try resolveMulti(testing.allocator, am, 30);
    defer testing.allocator.free(result);

    try testing.expectApproxEqAbs(@as(f64, 50.0), result[0], 0.001);
    try testing.expectApproxEqAbs(@as(f64, 100.0), result[1], 0.001);
}

test "resolveMulti: hold keyframe" {
    const vals0 = [_]f64{ 10, 20 };
    const vals1 = [_]f64{ 90, 80 };
    const kfs = [_]MultiKeyframe{
        .{ .time = 0, .values = &vals0, .ease_out = null, .ease_in = null, .hold = true },
        .{ .time = 60, .values = &vals1, .ease_out = null, .ease_in = null, .hold = false },
    };
    const am = AnimatedMulti{ .keyframed = &kfs };

    const result = try resolveMulti(testing.allocator, am, 30);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(f64, 10.0), result[0]);
    try testing.expectEqual(@as(f64, 20.0), result[1]);
}

// ---------------------------------------------------------------
// Compiler tests — resolveTransform
// ---------------------------------------------------------------

test "resolveTransform: static transform returns expected values" {
    const anchor_vals = [_]f64{ 50, 50, 0 };
    const pos_vals = [_]f64{ 100, 200, 0 };
    const scale_vals = [_]f64{ 50, 75, 100 };

    const tr = Transform{
        .anchor = AnimatedMulti{ .static = &anchor_vals },
        .position = AnimatedMulti{ .static = &pos_vals },
        .scale = AnimatedMulti{ .static = &scale_vals },
        .rotation = AnimatedValue{ .static = 45.0 },
        .opacity = AnimatedValue{ .static = 80.0 },
    };

    const resolved = try resolveTransform(testing.allocator, tr, 0);
    try testing.expectEqual(@as(f64, 50.0), resolved.anchor[0]);
    try testing.expectEqual(@as(f64, 50.0), resolved.anchor[1]);
    try testing.expectEqual(@as(f64, 100.0), resolved.position[0]);
    try testing.expectEqual(@as(f64, 200.0), resolved.position[1]);
    try testing.expectEqual(@as(f64, 50.0), resolved.scale[0]);
    try testing.expectEqual(@as(f64, 75.0), resolved.scale[1]);
    try testing.expectEqual(@as(f64, 45.0), resolved.rotation);
    try testing.expectEqual(@as(f64, 80.0), resolved.opacity);
}

test "resolveTransform: null fields use defaults" {
    const tr = Transform{
        .anchor = null,
        .position = null,
        .scale = null,
        .rotation = null,
        .opacity = null,
    };

    const resolved = try resolveTransform(testing.allocator, tr, 0);
    try testing.expectEqual(@as(f64, 0.0), resolved.anchor[0]);
    try testing.expectEqual(@as(f64, 0.0), resolved.position[0]);
    try testing.expectEqual(@as(f64, 100.0), resolved.scale[0]);
    try testing.expectEqual(@as(f64, 0.0), resolved.rotation);
    try testing.expectEqual(@as(f64, 100.0), resolved.opacity);
}

// ---------------------------------------------------------------
// Compiler tests — compileFrame
// ---------------------------------------------------------------

test "compileFrame: minimal animation" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "o":{"a":0,"k":100},
        \\    "p":{"a":0,"k":[50,50,0]}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const frame = try compileFrame(testing.allocator, &anim, 0);
    defer frame.deinit();

    try testing.expectEqual(@as(f64, 0.0), frame.frame);
    try testing.expectEqual(@as(usize, 1), frame.layers.len);
    try testing.expect(frame.layers[0].visible);
    try testing.expect(frame.layers[0].transform != null);
    try testing.expectEqual(@as(f64, 100.0), frame.layers[0].transform.?.opacity);
    try testing.expectEqual(@as(f64, 50.0), frame.layers[0].transform.?.position[0]);
}

test "compileFrame: layer visibility based on timing" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":10,"op":50}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    // Before layer starts
    const f0 = try compileFrame(testing.allocator, &anim, 5);
    defer f0.deinit();
    try testing.expect(!f0.layers[0].visible);

    // During layer
    const f1 = try compileFrame(testing.allocator, &anim, 25);
    defer f1.deinit();
    try testing.expect(f1.layers[0].visible);

    // After layer ends
    const f2 = try compileFrame(testing.allocator, &anim, 55);
    defer f2.deinit();
    try testing.expect(!f2.layers[0].visible);
}

test "compileFrame: animated opacity resolves at frame" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "o":{"a":1,"k":[
        \\      {"t":0,"s":[100]},
        \\      {"t":60,"s":[0]}
        \\    ]}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const f30 = try compileFrame(testing.allocator, &anim, 30);
    defer f30.deinit();

    try testing.expectApproxEqAbs(@as(f64, 50.0), f30.layers[0].transform.?.opacity, 0.1);
}

test "compileFrame: shape properties resolved" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"shapes":[
        \\    {"ty":"rc","s":{"a":0,"k":[200,100]},"p":{"a":0,"k":[50,50]},"r":{"a":0,"k":10}},
        \\    {"ty":"fl","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":80}}
        \\  ]}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const frame = try compileFrame(testing.allocator, &anim, 0);
    defer frame.deinit();

    try testing.expectEqual(@as(usize, 2), frame.layers[0].shapes.len);

    // Rectangle
    const rect = frame.layers[0].shapes[0];
    try testing.expectEqual(ShapeType.rectangle, rect.ty);
    try testing.expect(rect.size != null);
    try testing.expectEqual(@as(f64, 200.0), rect.size.?[0]);
    try testing.expectEqual(@as(f64, 100.0), rect.size.?[1]);
    try testing.expectEqual(@as(f64, 10.0), rect.roundness.?);

    // Fill
    const fill = frame.layers[0].shapes[1];
    try testing.expectEqual(ShapeType.fill, fill.ty);
    try testing.expectEqual(@as(f64, 1.0), fill.color.?[0]);
    try testing.expectEqual(@as(f64, 0.0), fill.color.?[1]);
    try testing.expectEqual(@as(f64, 80.0), fill.opacity.?);
}

// ---------------------------------------------------------------
// Compiler tests — compile (full animation)
// ---------------------------------------------------------------

test "compile: produces correct number of frames" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const compiled = try compile(testing.allocator, &anim);
    defer compiled.deinit();

    try testing.expectEqual(@as(usize, 60), compiled.frames.len);
    try testing.expectEqual(@as(f64, 30.0), compiled.frame_rate);
    try testing.expectEqual(@as(u32, 100), compiled.width);
    try testing.expectEqual(@as(u32, 100), compiled.height);
}

test "compile: frame times are sequential" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":10,"w":100,"h":100,"layers":[]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const compiled = try compile(testing.allocator, &anim);
    defer compiled.deinit();

    for (compiled.frames, 0..) |frame, i| {
        try testing.expectEqual(@as(f64, @floatFromInt(i)), frame.frame);
    }
}

test "compile: animated values change across frames" {
    const json =
        \\{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[
        \\  {"ty":4,"ip":0,"op":60,"ks":{
        \\    "o":{"a":1,"k":[
        \\      {"t":0,"s":[100]},
        \\      {"t":60,"s":[0]}
        \\    ]}
        \\  }}
        \\]}
    ;
    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const compiled = try compile(testing.allocator, &anim);
    defer compiled.deinit();

    // Opacity should decrease from 100 to 0 over 60 frames
    const opacity_0 = compiled.frames[0].layers[0].transform.?.opacity;
    const opacity_30 = compiled.frames[30].layers[0].transform.?.opacity;
    const opacity_59 = compiled.frames[59].layers[0].transform.?.opacity;

    try testing.expectApproxEqAbs(@as(f64, 100.0), opacity_0, 0.1);
    try testing.expectApproxEqAbs(@as(f64, 50.0), opacity_30, 0.1);
    try testing.expect(opacity_59 < 5.0);
}

// ---------------------------------------------------------------
// Compiler integration tests — fixtures
// ---------------------------------------------------------------

test "compile fixture: many_layers.json" {
    const json = try readFixture("test/fixtures/many_layers.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    // Compile just a few sample frames to test, not the whole animation
    const f0 = try compileFrame(testing.allocator, &anim, 0);
    defer f0.deinit();
    try testing.expectEqual(@as(usize, 50), f0.layers.len);

    const f90 = try compileFrame(testing.allocator, &anim, 90);
    defer f90.deinit();
    try testing.expectEqual(@as(usize, 50), f90.layers.len);

    // Verify transforms are resolved (not null) for all visible layers
    for (f0.layers) |layer| {
        if (layer.visible) {
            try testing.expect(layer.transform != null);
        }
    }
}

test "compile fixture: many_keyframes.json" {
    const json = try readFixture("test/fixtures/many_keyframes.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    // Sample frames at start, middle, end
    const f0 = try compileFrame(testing.allocator, &anim, 0);
    defer f0.deinit();

    const f120 = try compileFrame(testing.allocator, &anim, 120);
    defer f120.deinit();

    const f239 = try compileFrame(testing.allocator, &anim, 239);
    defer f239.deinit();

    // All layers should have resolved transforms at all frames
    for (f120.layers) |layer| {
        if (layer.visible) {
            try testing.expect(layer.transform != null);
        }
    }

    // Orbiter positions should differ between frames (they animate)
    if (f0.layers.len > 1 and f120.layers.len > 1) {
        const pos0 = f0.layers[1].transform.?.position;
        const pos120 = f120.layers[1].transform.?.position;
        // At least one coordinate should differ
        try testing.expect(pos0[0] != pos120[0] or pos0[1] != pos120[1]);
    }
}

test "compile fixture: deep_nesting.json" {
    const json = try readFixture("test/fixtures/deep_nesting.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const f0 = try compileFrame(testing.allocator, &anim, 0);
    defer f0.deinit();

    const f75 = try compileFrame(testing.allocator, &anim, 75);
    defer f75.deinit();

    // Verify nested shapes are resolved
    for (f0.layers) |layer| {
        if (layer.shapes.len > 0) {
            const group = layer.shapes[0];
            try testing.expect(group.items.len > 0);
        }
    }
}

test "compile fixture: kitchen_sink.json" {
    const json = try readFixture("test/fixtures/kitchen_sink.json");
    defer testing.allocator.free(json);

    const anim = try parse(testing.allocator, json);
    defer anim.deinit();

    const f0 = try compileFrame(testing.allocator, &anim, 0);
    defer f0.deinit();

    const f150 = try compileFrame(testing.allocator, &anim, 150);
    defer f150.deinit();

    try testing.expectEqual(@as(usize, 20), f0.layers.len);

    // Verify mix of visible/non-visible layers at frame 0
    var visible_count: usize = 0;
    for (f0.layers) |layer| {
        if (layer.visible) visible_count += 1;
    }
    try testing.expect(visible_count > 0);
}
