//! Explicit state-transition graph for deterministic workflow validation.
const std = @import("std");

pub fn StateGraph(comptime State: type, comptime Edge: type) type {
    return struct {
        transitions: []const Transition,

        pub const Transition = struct {
            from: State,
            edge: Edge,
            to: State,
        };

        pub fn next(self: @This(), from: State, edge: Edge) error{
            UndefinedTransition,
            AmbiguousTransition,
        }!State {
            var result: ?State = null;
            for (self.transitions) |transition| {
                if (transition.from == from and transition.edge == edge) {
                    if (result != null) return error.AmbiguousTransition;
                    result = transition.to;
                }
            }
            return result orelse error.UndefinedTransition;
        }
    };
}

test "state graph refuses undefined and ambiguous transitions" {
    const State = enum { ready, running, stopped };
    const Edge = enum { start, stop };
    const Graph = StateGraph(State, Edge);
    const graph: Graph = .{ .transitions = &.{
        .{ .from = .ready, .edge = .start, .to = .running },
        .{ .from = .running, .edge = .stop, .to = .stopped },
    } };
    try std.testing.expectEqual(State.running, try graph.next(.ready, .start));
    try std.testing.expectError(error.UndefinedTransition, graph.next(.ready, .stop));
}
