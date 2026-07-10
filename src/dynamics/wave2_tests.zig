//! Isolated Wave 2 test root. This remains separate until the parent lane
//! elects to expose these modules from src/root.zig and build.zig.

const math = @import("math.zig");
const rigid_body = @import("rigid_body.zig");
const gravity = @import("../environment/gravity.zig");
const coefficient_table = @import("../aero/coefficient_table.zig");
const mass_properties = @import("../vehicle/mass_properties.zig");
const actuator = @import("../control/actuator.zig");
const pid = @import("../control/pid.zig");
const noise = @import("../sensor/noise.zig");
const imu = @import("../sensor/imu.zig");
const gnss = @import("../sensor/gnss.zig");

test {
    _ = math;
    _ = rigid_body;
    _ = gravity;
    _ = coefficient_table;
    _ = mass_properties;
    _ = actuator;
    _ = pid;
    _ = noise;
    _ = imu;
    _ = gnss;
}
