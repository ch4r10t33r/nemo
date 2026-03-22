const std = @import("std");

pub const Checkpoint = struct {
    slot: u64,
    root: []const u8,
};

pub const ForkNode = struct {
    root: []const u8,
    slot: u64,
    parent_root: []const u8,
    proposer_index: u64,
    weight: u64,
};

pub const ForkChoice = struct {
    nodes: []ForkNode,
    head: []const u8,
    justified: Checkpoint,
    finalized: Checkpoint,
    safe_target: []const u8,
    validator_count: u64,
};

pub const Health = struct {
    status: []const u8,
};
