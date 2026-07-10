//! Bounded layered scene contracts inspired by OpenUSD composition concepts.
//! This is an independent compact contract, not an OpenUSD implementation.
const std = @import("std");

pub const Token = u64;
pub const PayloadAvailability = enum { unloaded, available, unavailable };

pub const Reference = struct {
    asset: Token,
    prim: Token,
};

pub const VariantSelection = struct {
    set: Token,
    choice: Token,
};

pub const PrimSpec = struct {
    path: Token,
    active: ?bool = null,
    reference: ?Reference = null,
    payload_asset: ?Token = null,
    payload_availability: ?PayloadAvailability = null,
    variant: ?VariantSelection = null,
};

pub const ResolvedPrim = struct {
    path: Token,
    active: bool = true,
    reference: ?Reference = null,
    payload_asset: ?Token = null,
    payload_availability: PayloadAvailability = .unloaded,
    variant: ?VariantSelection = null,
    contributing_layers: u32 = 0,

    pub fn usable(self: ResolvedPrim) bool {
        return self.active and (self.payload_asset == null or self.payload_availability == .available);
    }
};

pub fn Layer(comptime prim_capacity: usize) type {
    return struct {
        id: Token,
        specs: [prim_capacity]PrimSpec = undefined,
        len: usize = 0,

        const Self = @This();
        pub const Error = error{LayerCapacityExceeded};

        pub fn add(self: *Self, spec: PrimSpec) Error!void {
            if (self.len == prim_capacity) return error.LayerCapacityExceeded;
            self.specs[self.len] = spec;
            self.len += 1;
        }
    };
}

/// Layers are added weak-to-strong. Stronger authored fields override weaker
/// fields while unauthored fields continue to compose through.
pub fn Scene(comptime layer_capacity: usize, comptime prim_capacity: usize) type {
    const LayerType = Layer(prim_capacity);
    return struct {
        layers: [layer_capacity]LayerType = undefined,
        len: usize = 0,

        const Self = @This();
        pub const Error = error{SceneLayerCapacityExceeded};

        pub fn addLayer(self: *Self, layer: LayerType) Error!void {
            if (self.len == layer_capacity) return error.SceneLayerCapacityExceeded;
            self.layers[self.len] = layer;
            self.len += 1;
        }

        pub fn resolve(self: *const Self, path: Token) ?ResolvedPrim {
            var result = ResolvedPrim{ .path = path };
            var found = false;
            for (self.layers[0..self.len]) |layer| {
                for (layer.specs[0..layer.len]) |spec| {
                    if (spec.path != path) continue;
                    found = true;
                    result.contributing_layers += 1;
                    if (spec.active) |active| result.active = active;
                    if (spec.reference) |reference| result.reference = reference;
                    if (spec.payload_asset) |asset| result.payload_asset = asset;
                    if (spec.payload_availability) |availability|
                        result.payload_availability = availability;
                    if (spec.variant) |variant| result.variant = variant;
                }
            }
            return if (found) result else null;
        }
    };
}

test "strong layers select variants without hiding weak references" {
    const L = Layer(4);
    var base = L{ .id = 1 };
    try base.add(.{
        .path = 10,
        .reference = .{ .asset = 20, .prim = 30 },
        .payload_asset = 40,
        .payload_availability = .available,
    });
    var mission = L{ .id = 2 };
    try mission.add(.{
        .path = 10,
        .variant = .{ .set = 50, .choice = 51 },
        .payload_availability = .unavailable,
    });
    var scene = Scene(2, 4){};
    try scene.addLayer(base);
    try scene.addLayer(mission);
    const prim = scene.resolve(10).?;
    try std.testing.expectEqual(@as(Token, 20), prim.reference.?.asset);
    try std.testing.expectEqual(@as(Token, 51), prim.variant.?.choice);
    try std.testing.expect(!prim.usable());
    try std.testing.expectEqual(@as(u32, 2), prim.contributing_layers);
}
