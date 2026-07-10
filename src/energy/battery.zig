//! Bounded lumped battery accounting with OCV, resistance, SOC, and thermal state.
//! Parameters are caller-supplied; this module does not claim cell identification.

const std = @import("std");

pub const Config = struct {
    capacity_coulomb: f64,
    ocv_empty_v: f64,
    ocv_full_v: f64,
    internal_resistance_ohm: f64,
    maximum_discharge_current_a: f64,
    thermal_capacity_j_per_k: f64,
    cooling_w_per_k: f64,
    ambient_temperature_k: f64,

    pub fn validate(self: Config) error{InvalidConfiguration}!void {
        const values = [_]f64{
            self.capacity_coulomb,
            self.ocv_empty_v,
            self.ocv_full_v,
            self.internal_resistance_ohm,
            self.maximum_discharge_current_a,
            self.thermal_capacity_j_per_k,
            self.cooling_w_per_k,
            self.ambient_temperature_k,
        };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidConfiguration;
        if (!(self.capacity_coulomb > 0.0) or !(self.ocv_empty_v > 0.0) or
            !(self.ocv_full_v >= self.ocv_empty_v) or self.internal_resistance_ohm < 0.0 or
            !(self.maximum_discharge_current_a > 0.0) or !(self.thermal_capacity_j_per_k > 0.0) or
            self.cooling_w_per_k < 0.0 or !(self.ambient_temperature_k > 0.0))
            return error.InvalidConfiguration;
    }
};

pub const Battery = struct {
    config: Config,
    state_of_charge: f64,
    thermal_energy_above_ambient_j: f64 = 0.0,
    chemical_energy_drawn_j: f64 = 0.0,
    terminal_energy_delivered_j: f64 = 0.0,
    ohmic_heat_generated_j: f64 = 0.0,
    heat_rejected_j: f64 = 0.0,

    pub fn init(config: Config, state_of_charge: f64, temperature_k: f64) error{InvalidInitialState}!Battery {
        config.validate() catch return error.InvalidInitialState;
        if (!std.math.isFinite(state_of_charge) or state_of_charge < 0.0 or state_of_charge > 1.0 or
            !std.math.isFinite(temperature_k) or temperature_k < config.ambient_temperature_k)
            return error.InvalidInitialState;
        return .{
            .config = config,
            .state_of_charge = state_of_charge,
            .thermal_energy_above_ambient_j = (temperature_k - config.ambient_temperature_k) * config.thermal_capacity_j_per_k,
        };
    }

    pub fn openCircuitVoltage(self: Battery) f64 {
        return self.config.ocv_empty_v +
            self.state_of_charge * (self.config.ocv_full_v - self.config.ocv_empty_v);
    }

    pub fn temperatureK(self: Battery) f64 {
        return self.config.ambient_temperature_k +
            self.thermal_energy_above_ambient_j / self.config.thermal_capacity_j_per_k;
    }

    /// Supplies a nonnegative electrical power request for one fixed step.
    pub fn stepPower(self: *Battery, requested_power_w: f64, dt_s: f64) error{InvalidStep}!Step {
        if (!std.math.isFinite(requested_power_w) or requested_power_w < 0.0 or
            !std.math.isFinite(dt_s) or !(dt_s > 0.0))
            return error.InvalidStep;

        const ocv = self.openCircuitVoltage();
        const resistance = self.config.internal_resistance_ohm;
        var current: f64 = 0.0;
        var power_limited = false;
        if (requested_power_w > 0.0 and self.state_of_charge > 0.0) {
            if (resistance == 0.0) {
                current = requested_power_w / ocv;
            } else {
                const discriminant = ocv * ocv - 4.0 * resistance * requested_power_w;
                if (discriminant <= 0.0) {
                    current = ocv / (2.0 * resistance);
                    power_limited = true;
                } else {
                    // Stable small root of R I^2 - OCV I + P = 0.
                    current = 2.0 * requested_power_w / (ocv + @sqrt(discriminant));
                }
            }
        } else if (requested_power_w > 0.0) {
            power_limited = true;
        }
        if (current > self.config.maximum_discharge_current_a) {
            current = self.config.maximum_discharge_current_a;
            power_limited = true;
        }
        const charge_available_c = self.state_of_charge * self.config.capacity_coulomb;
        if (current * dt_s > charge_available_c) {
            current = charge_available_c / dt_s;
            power_limited = true;
        }

        const terminal_voltage = @max(0.0, ocv - resistance * current);
        const terminal_power = terminal_voltage * current;
        if (terminal_power + 1e-12 < requested_power_w) power_limited = true;
        const chemical_energy = ocv * current * dt_s;
        const terminal_energy = terminal_power * dt_s;
        const ohmic_heat = resistance * current * current * dt_s;
        const temperature_difference = self.temperatureK() - self.config.ambient_temperature_k;
        const possible_cooling = self.config.cooling_w_per_k * @max(0.0, temperature_difference) * dt_s;
        const heat_rejected = @min(self.thermal_energy_above_ambient_j + ohmic_heat, possible_cooling);

        self.state_of_charge = std.math.clamp(
            self.state_of_charge - current * dt_s / self.config.capacity_coulomb,
            0.0,
            1.0,
        );
        self.thermal_energy_above_ambient_j = @max(
            0.0,
            self.thermal_energy_above_ambient_j + ohmic_heat - heat_rejected,
        );
        self.chemical_energy_drawn_j += chemical_energy;
        self.terminal_energy_delivered_j += terminal_energy;
        self.ohmic_heat_generated_j += ohmic_heat;
        self.heat_rejected_j += heat_rejected;

        return .{
            .open_circuit_voltage_v = ocv,
            .terminal_voltage_v = terminal_voltage,
            .current_a = current,
            .requested_power_w = requested_power_w,
            .delivered_power_w = terminal_power,
            .chemical_energy_j = chemical_energy,
            .terminal_energy_j = terminal_energy,
            .ohmic_heat_j = ohmic_heat,
            .heat_rejected_j = heat_rejected,
            .power_limited = power_limited,
            .depleted = self.state_of_charge == 0.0,
        };
    }
};

pub const Step = struct {
    open_circuit_voltage_v: f64,
    terminal_voltage_v: f64,
    current_a: f64,
    requested_power_w: f64,
    delivered_power_w: f64,
    chemical_energy_j: f64,
    terminal_energy_j: f64,
    ohmic_heat_j: f64,
    heat_rejected_j: f64,
    power_limited: bool,
    depleted: bool,
};

fn testConfig() Config {
    return .{
        .capacity_coulomb = 3600.0,
        .ocv_empty_v = 12.0,
        .ocv_full_v = 16.0,
        .internal_resistance_ohm = 0.1,
        .maximum_discharge_current_a = 20.0,
        .thermal_capacity_j_per_k = 100.0,
        .cooling_w_per_k = 1.0,
        .ambient_temperature_k = 293.15,
    };
}

test "battery energy accounting conserves chemical input" {
    var battery = try Battery.init(testConfig(), 1.0, 293.15);
    const result = try battery.stepPower(100.0, 1.0);
    try std.testing.expectApproxEqAbs(
        result.chemical_energy_j,
        result.terminal_energy_j + result.ohmic_heat_j,
        1e-10,
    );
    try std.testing.expectApproxEqAbs(
        battery.chemical_energy_drawn_j,
        battery.terminal_energy_delivered_j + battery.ohmic_heat_generated_j,
        1e-10,
    );
    try std.testing.expect(battery.state_of_charge < 1.0);
    try std.testing.expect(battery.temperatureK() >= battery.config.ambient_temperature_k);
    try std.testing.expectApproxEqAbs(
        battery.thermal_energy_above_ambient_j,
        battery.ohmic_heat_generated_j - battery.heat_rejected_j,
        1e-12,
    );
}

test "battery current, SOC, voltage, and thermal state remain bounded" {
    var battery = try Battery.init(testConfig(), 0.001, 300.0);
    const result = try battery.stepPower(1e9, 10.0);
    try std.testing.expect(result.power_limited);
    try std.testing.expect(result.current_a <= battery.config.maximum_discharge_current_a);
    try std.testing.expect(battery.state_of_charge >= 0.0 and battery.state_of_charge <= 1.0);
    try std.testing.expect(result.terminal_voltage_v >= 0.0);
    try std.testing.expect(battery.thermal_energy_above_ambient_j >= 0.0);
}

test "battery stepping is deterministic" {
    var first = try Battery.init(testConfig(), 0.8, 295.0);
    var second = first;
    for (0..50) |_| {
        const a = try first.stepPower(80.0, 0.02);
        const b = try second.stepPower(80.0, 0.02);
        try std.testing.expectEqualDeep(a, b);
    }
    try std.testing.expectEqualDeep(first, second);
}
