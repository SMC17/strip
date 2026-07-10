//! Public-safe, domain-generic resilience abstractions.
//! This surface models detection and bounded response, not targeting or effects.
const std = @import("std");

pub const ObservationClass = enum { nominal, anomalous, unknown };
pub const Response = enum { continue_monitoring, isolate_component, enter_safe_state, request_human_review };

pub const Assessment = struct {
    class: ObservationClass,
    confidence: f64,
    source_count: u32,
};

pub fn boundedResponse(assessment: Assessment) Response {
    if (!std.math.isFinite(assessment.confidence) or
        assessment.confidence < 0 or
        assessment.confidence > 1 or
        assessment.source_count == 0)
        return .request_human_review;
    return switch (assessment.class) {
        .nominal => .continue_monitoring,
        .unknown => .request_human_review,
        .anomalous => if (assessment.confidence >= 0.9)
            .isolate_component
        else
            .enter_safe_state,
    };
}

test "invalid or unsupported assessments require review" {
    try std.testing.expectEqual(Response.request_human_review, boundedResponse(.{
        .class = .anomalous,
        .confidence = 1.1,
        .source_count = 2,
    }));
    try std.testing.expectEqual(Response.enter_safe_state, boundedResponse(.{
        .class = .anomalous,
        .confidence = 0.7,
        .source_count = 2,
    }));
}
