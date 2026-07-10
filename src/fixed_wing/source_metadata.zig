//! Provenance boundary for future F-16 data ingestion.
//!
//! NASA Technical Paper 1538 is referenced as a candidate public source. No
//! numeric table from that publication is embedded or represented as validated
//! here. Runtime tests use explicitly synthetic coefficients.

pub const nasa_tp_1538 = .{
    .publication = "NASA Technical Paper 1538",
    .locator = "NASA Technical Reports Server publication-number TP-1538",
    .role = "provenance scaffold for future independently transcribed and audited F-16 aerodynamic data",
    .data_included = false,
    .validation_status = "not_ingested_not_validated",
};
