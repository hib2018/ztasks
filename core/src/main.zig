const std = @import("std");
const core = @import("ztasks_core");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 4 or !std.mem.eql(u8, args[1], "serve") or !std.mem.eql(u8, args[2], "--project-root")) {
        return error.InvalidArguments;
    }
    var source_locator: ?[]const u8 = null;
    if (args.len == 6 and std.mem.eql(u8, args[4], "--source")) source_locator = args[5];

    var stdin_buffer: [core.protocol_request.max_line_size + 2]u8 = undefined;
    var stdin_file_reader: std.Io.File.Reader = .init(.stdin(), init.io, &stdin_buffer);
    const reader = &stdin_file_reader.interface;
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    while (try reader.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const response = try core.protocol_handler.handleLine(.{
            .allocator = allocator,
            .io = init.io,
            .project_root = args[3],
            .source_locator = source_locator,
        }, line);
        try writer.writeAll(response);
        try writer.writeByte('\n');
        try writer.flush();
    }
}

test {
    _ = core;
}
