//! Method anchors only. These records do not import software or confer qualification.

pub const Source = struct {
    id: []const u8,
    title: []const u8,
    publisher_or_authors: []const u8,
    locator: []const u8,
    concepts_used: []const []const u8,
    limitation: []const u8,
};

pub const sources = [_]Source{
    .{
        .id = "nasa-sidpac-lar-16100-1",
        .title = "System IDentification Programs for AirCraft (SIDPAC)",
        .publisher_or_authors = "NASA Software Catalog; associated work by Eugene A. Morelli",
        .locator = "https://software.nasa.gov/software/LAR-16100-1",
        .concepts_used = &.{
            "designed excitation maneuvers",
            "parameter estimation",
            "residual diagnostics",
            "independent model validation",
        },
        .limitation = "Catalog and methodological grounding only; SIDPAC software is neither bundled nor claimed equivalent.",
    },
    .{
        .id = "morelli-klein-aircraft-system-identification",
        .title = "Aircraft System Identification: Theory and Practice",
        .publisher_or_authors = "Eugene A. Morelli and Vladislav Klein",
        .locator = "ISBN 978-0-9974306-1-6",
        .concepts_used = &.{
            "flight-test experiment design",
            "ordinary and weighted least squares",
            "covariance and identifiability",
            "prediction residual analysis",
        },
        .limitation = "Conceptual metadata only; this bounded implementation is not a reproduction of the referenced tooling.",
    },
    .{
        .id = "faa-14-cfr-part-60",
        .title = "14 CFR Part 60—Flight Simulation Training Device Initial and Continuing Qualification and Use",
        .publisher_or_authors = "Federal Aviation Administration / eCFR",
        .locator = "https://www.ecfr.gov/current/title-14/chapter-I/subchapter-G/part-60",
        .concepts_used = &.{
            "configuration identity",
            "objective test records",
            "test tolerances and evidence retention",
            "latency and transport-delay records",
        },
        .limitation = "Part 60 concepts inform evidence structure only; no FSTD, operational, certification, or qualification compliance is claimed.",
    },
};

test "metadata carries explicit no-qualification boundary" {
    try @import("std").testing.expect(sources.len == 3);
    for (sources) |source|
        try @import("std").testing.expect(source.limitation.len > 0);
}
