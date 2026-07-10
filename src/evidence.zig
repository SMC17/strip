//! Evidence metadata that must accompany an engineering result.

pub const ProofLevel = enum {
    implemented,
    unit_tested,
    analytical,
    cross_implementation,
    public_benchmark,
    experimental,
    hil_validated,
    accredited_use,
    certification_evidence,
};

pub const IntendedUse = enum {
    education,
    research,
    preliminary_design,
    simulation_training,
};

pub const ValidityStatus = enum {
    valid,
    outside_envelope,
    invalid_input,
};

pub const ModelManifest = struct {
    id: []const u8,
    version: []const u8,
    proof_level: ProofLevel,
    source: []const u8,
    assumptions: []const []const u8,
    valid_min: f64,
    valid_max: f64,
    valid_unit: []const u8,
};

pub const Context = struct {
    intended_use: IntendedUse,
    spatial_frame: ?[]const u8 = null,
    time_reference: ?[]const u8 = null,
};
