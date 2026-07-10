//! Strip interoperability layer.
pub const common = @import("common.zig");
pub const contracts = @import("contracts.zig");
pub const fmi3 = @import("fmi3.zig");
pub const mavlink = @import("mavlink.zig");
pub const hla_dis = @import("hla_dis.zig");

test {
    _ = common;
    _ = contracts;
    _ = fmi3;
    _ = mavlink;
    _ = hla_dis;
}
