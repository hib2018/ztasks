const std = @import("std");

pub const identifier_limit = 128;
pub const message_limit = 4096;
pub const source_locator_limit = 4096;
pub const title_scalar_limit = 200;
pub const event_limit = 65_536;

pub const Redaction = struct {
    field: []const u8,
    class: []const u8,
};

pub const SanitizedText = struct {
    value: []u8,
    redactions: []Redaction,

    pub fn deinit(self: SanitizedText, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
        allocator.free(self.redactions);
    }
};

pub fn validateIdentifier(value: []const u8) !void {
    try validateRequiredText(value, identifier_limit, false);
}

pub fn validateTitle(value: []const u8) !void {
    try validateUtf8AndControls(value, false);
    if (std.mem.trim(u8, value, " \t\r\n").len == 0) return error.InvalidText;
    const scalar_count = std.unicode.utf8CountCodepoints(value) catch return error.InvalidText;
    if (scalar_count > title_scalar_limit) return error.FieldTooLarge;
}

pub fn validateMessage(value: []const u8) !void {
    try validateRequiredText(value, message_limit, true);
}

pub fn validateSourceLocator(value: []const u8) !void {
    try validateRequiredText(value, source_locator_limit, false);
    if (std.fs.path.isAbsolute(value) or std.mem.indexOfScalar(u8, value, '\\') != null) {
        return error.InvalidSourceLocator;
    }
    var components = std.mem.splitScalar(u8, value, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
            return error.InvalidSourceLocator;
        }
    }
}

pub fn validateRequiredText(value: []const u8, max_bytes: usize, allow_multiline: bool) !void {
    if (value.len > max_bytes) return error.FieldTooLarge;
    if (std.mem.trim(u8, value, " \t\r\n").len == 0) return error.InvalidText;
    try validateUtf8AndControls(value, allow_multiline);
}

fn validateUtf8AndControls(value: []const u8, allow_multiline: bool) !void {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidText;
    var view = std.unicode.Utf8View.initUnchecked(value);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        const permitted_multiline = allow_multiline and (codepoint == '\n' or codepoint == '\t');
        if ((codepoint <= 0x1f or (codepoint >= 0x7f and codepoint <= 0x9f)) and !permitted_multiline) {
            return error.InvalidText;
        }
        if ((codepoint >= 0x202a and codepoint <= 0x202e) or
            (codepoint >= 0x2066 and codepoint <= 0x2069))
        {
            return error.InvalidText;
        }
    }
}

pub fn isProhibitedField(field: []const u8) bool {
    var normalized: [64]u8 = undefined;
    var length: usize = 0;
    for (field) |byte| {
        if (byte == '_' or byte == '-' or byte == '.' or byte == ' ') continue;
        if (length == normalized.len) return true;
        normalized[length] = std.ascii.toLower(byte);
        length += 1;
    }
    const candidate = normalized[0..length];
    const prohibited = [_][]const u8{
        "privatereasoning", "reasoning",     "chainofthought", "transcript",
        "rawstdout",        "rawstderr",     "environment",    "headers",
        "cookies",          "authorization", "credentials",    "password",
        "secret",           "token",         "apikey",
    };
    for (prohibited) |name| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

pub fn sanitizeText(
    allocator: std.mem.Allocator,
    field: []const u8,
    value: []const u8,
) !SanitizedText {
    try validateMessage(value);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var redactions: std.ArrayList(Redaction) = .empty;
    defer redactions.deinit(allocator);
    var cursor: usize = 0;
    while (findRecognizedCredential(value[cursor..])) |relative| {
        const recognized = CredentialMatch{
            .start = cursor + relative.start,
            .end = cursor + relative.end,
            .prefix = relative.prefix,
            .class = relative.class,
        };
        try output.appendSlice(allocator, value[cursor..recognized.start]);
        try output.appendSlice(allocator, recognized.prefix);
        try output.appendSlice(allocator, "[REDACTED:");
        try output.appendSlice(allocator, recognized.class);
        try output.appendSlice(allocator, "]");
        try redactions.append(allocator, .{ .field = field, .class = recognized.class });
        cursor = recognized.end;
    }

    if (redactions.items.len != 0) {
        try output.appendSlice(allocator, value[cursor..]);
        const owned = try output.toOwnedSlice(allocator);
        errdefer allocator.free(owned);
        try validateMessage(owned);
        return .{ .value = owned, .redactions = try redactions.toOwnedSlice(allocator) };
    }

    return .{
        .value = try allocator.dupe(u8, value),
        .redactions = try allocator.alloc(Redaction, 0),
    };
}

const CredentialMatch = struct {
    start: usize,
    end: usize,
    prefix: []const u8 = "",
    class: []const u8,
};

fn findRecognizedCredential(value: []const u8) ?CredentialMatch {
    var best: ?CredentialMatch = null;
    if (findHeaderValue(value, "authorization:")) |range| {
        chooseEarlier(&best, .{ .start = range.start, .end = range.end, .class = "authorization" });
    }
    if (findHeaderValue(value, "cookie:")) |range| {
        chooseEarlier(&best, .{ .start = range.start, .end = range.end, .class = "cookie" });
    }

    const assignment_keys = [_][]const u8{ "password", "secret", "token", "api_key", "authorization" };
    for (assignment_keys) |key| {
        var pattern_buffer: [32]u8 = undefined;
        @memcpy(pattern_buffer[0..key.len], key);
        pattern_buffer[key.len] = '=';
        const pattern = pattern_buffer[0 .. key.len + 1];
        if (indexOfIgnoreCase(value, pattern)) |position| {
            const secret_start = position + pattern.len;
            if (secret_start == value.len) continue;
            chooseEarlier(&best, .{
                .start = secret_start,
                .end = credentialEnd(value, secret_start),
                .class = if (std.mem.eql(u8, key, "api_key")) "api-key" else key,
            });
        }
    }

    const pem_begin = "-----BEGIN PRIVATE KEY-----";
    const pem_end = "-----END PRIVATE KEY-----";
    if (std.mem.indexOf(u8, value, pem_begin)) |start| {
        const rest = value[start + pem_begin.len ..];
        const end_offset = std.mem.indexOf(u8, rest, pem_end) orelse rest.len;
        const end = @min(value.len, start + pem_begin.len + end_offset + pem_end.len);
        chooseEarlier(&best, .{ .start = start, .end = end, .class = "private-key" });
    }

    if (findUriPassword(value)) |range| {
        chooseEarlier(&best, .{ .start = range.start, .end = range.end, .class = "uri-password" });
    }

    const provider_prefixes = [_][]const u8{ "ghp_", "github_pat_", "sk-", "AKIA" };
    for (provider_prefixes) |prefix| {
        if (std.mem.indexOf(u8, value, prefix)) |start| {
            chooseEarlier(&best, .{ .start = start, .end = credentialEnd(value, start), .class = "provider-token" });
        }
    }
    return best;
}

const ByteRange = struct { start: usize, end: usize };

fn findHeaderValue(value: []const u8, header: []const u8) ?ByteRange {
    const position = indexOfIgnoreCase(value, header) orelse return null;
    var start = position + header.len;
    while (start < value.len and (value[start] == ' ' or value[start] == '\t')) : (start += 1) {}
    if (start == value.len) return null;
    var end = start;
    while (end < value.len and value[end] != '\n' and value[end] != '\r') : (end += 1) {}
    return .{ .start = start, .end = end };
}

fn findUriPassword(value: []const u8) ?ByteRange {
    const scheme = std.mem.indexOf(u8, value, "://") orelse return null;
    const authority_start = scheme + 3;
    const authority_end = std.mem.indexOfAnyPos(u8, value, authority_start, "/ \t\r\n") orelse value.len;
    const at = std.mem.indexOfScalarPos(u8, value, authority_start, '@') orelse return null;
    if (at >= authority_end) return null;
    const colon = std.mem.indexOfScalarPos(u8, value, authority_start, ':') orelse return null;
    if (colon >= at or colon + 1 == at) return null;
    return .{ .start = colon + 1, .end = at };
}

fn chooseEarlier(best: *?CredentialMatch, candidate: CredentialMatch) void {
    if (candidate.end <= candidate.start) return;
    if (best.* == null or candidate.start < best.*.?.start) best.* = candidate;
}

fn credentialEnd(value: []const u8, start: usize) usize {
    var end = start;
    while (end < value.len) : (end += 1) {
        if (value[end] == '\n' or value[end] == '\r' or value[end] == '&' or value[end] == ' ') break;
    }
    return end;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

test "identifier boundaries are measured as UTF-8 bytes" {
    const exact = "a" ** 128;
    const over = "a" ** 129;
    try validateIdentifier(exact);
    try std.testing.expectError(error.FieldTooLarge, validateIdentifier(over));
}

test "titles use scalar limits and reject unsafe controls" {
    const exact = "界" ** 200;
    const over = "界" ** 201;
    try validateTitle(exact);
    try std.testing.expectError(error.FieldTooLarge, validateTitle(over));
    try std.testing.expectError(error.InvalidText, validateTitle("bad\x1b[31m"));
}

test "permitted multiline text rejects unsafe controls" {
    try validateMessage("line one\n\tline two");
    try std.testing.expectError(error.InvalidText, validateMessage("value\x00"));
}

test "prohibited fields are case and separator normalized" {
    try std.testing.expect(isProhibitedField("private_reasoning"));
    try std.testing.expect(isProhibitedField("API-Key"));
    try std.testing.expect(!isProhibitedField("current_action"));
}

test "recognized credentials are replaced without retaining originals" {
    const result = try sanitizeText(std.testing.allocator, "payload.message", "token=super-secret-value");
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("token=[REDACTED:token]", result.value);
    try std.testing.expectEqual(@as(usize, 1), result.redactions.len);
    try std.testing.expectEqualStrings("token", result.redactions[0].class);
    try std.testing.expect(std.mem.indexOf(u8, result.value, "super-secret-value") == null);
}

test "all deterministic credential classes are sanitized" {
    const cases = [_]struct { input: []const u8, marker: []const u8 }{
        .{ .input = "Authorization: Bearer abcdef123456", .marker = "[REDACTED:authorization]" },
        .{ .input = "Cookie: session=abcdef123456", .marker = "[REDACTED:cookie]" },
        .{ .input = "-----BEGIN PRIVATE KEY-----\nabcdef\n-----END PRIVATE KEY-----", .marker = "[REDACTED:private-key]" },
        .{ .input = "https://user:password@example.test/path", .marker = "[REDACTED:uri-password]" },
        .{ .input = "credential ghp_abcdef123456", .marker = "[REDACTED:provider-token]" },
    };
    for (cases) |case| {
        const result = try sanitizeText(std.testing.allocator, "payload.message", case.input);
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(std.mem.indexOf(u8, result.value, case.marker) != null);
        try std.testing.expectEqual(@as(usize, 1), result.redactions.len);
    }
}

test "multiple credentials are all sanitized and unknown forms remain caller responsibility" {
    const multiple = try sanitizeText(std.testing.allocator, "payload.message", "token=first secret=second");
    defer multiple.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), multiple.redactions.len);
    try std.testing.expect(std.mem.indexOf(u8, multiple.value, "first") == null);
    try std.testing.expect(std.mem.indexOf(u8, multiple.value, "second") == null);

    const unknown = try sanitizeText(std.testing.allocator, "payload.message", "opaque-sensitive-material");
    defer unknown.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("opaque-sensitive-material", unknown.value);
    try std.testing.expectEqual(@as(usize, 0), unknown.redactions.len);
}
