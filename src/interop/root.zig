//! Strip interoperability layer.
pub const common = @import("common.zig");
pub const contracts = @import("contracts.zig");
pub const fmi3 = @import("fmi3.zig");
pub const mavlink = @import("mavlink.zig");
pub const mavlink_v2 = @import("mavlink_v2.zig");
pub const mavlink_sitl = @import("mavlink_sitl.zig");
pub const hla_dis = @import("hla_dis.zig");

test {
    _ = common;
    _ = contracts;
    _ = fmi3;
    _ = mavlink;
    _ = mavlink_v2;
    _ = mavlink_sitl;
    _ = hla_dis;
}
