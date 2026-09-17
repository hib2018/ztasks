const std = @import("std");

pub const product_version = "0.1.0-dev";
pub const protocol_version: u8 = 1;
pub const data_version: u8 = 1;

pub const Report = struct {
    product_version: []const u8 = product_version,
    protocol_version: u8 = protocol_version,
    data_version: u8 = data_version,
    capabilities: []const []const u8,
};

pub fn compatible(product: []const u8, protocol: u8, data: u8) bool {
    return std.mem.eql(u8, product, product_version) and protocol == protocol_version and data == data_version;
}

test "compatibility requires matching product protocol and data versions" {
    try std.testing.expect(compatible(product_version, 1, 1));
    try std.testing.expect(!compatible("0.2.0", 1, 1));
    try std.testing.expect(!compatible(product_version, 2, 1));
    try std.testing.expect(!compatible(product_version, 1, 2));
}
