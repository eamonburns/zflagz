const std = @import("std");
const mem = std.mem;

const log = std.log.scoped(.zflagz);

pub const Args = struct {
    it: *std.process.Args.Iterator,
    current: ?[:0]const u8,

    gpa: mem.Allocator,
    help_text: HelpText,

    /// You should not use `it` after passing it here,
    /// since the `Args` could have consumed an argument from
    /// `it` without returning it yet.
    pub fn init(gpa: mem.Allocator, it: *std.process.Args.Iterator) Args {
        return .{
            .it = it,
            .current = null,
            .gpa = gpa,
            .help_text = .init,
        };
    }

    pub fn peek(args: *Args) ?[:0]const u8 {
        if (args.current) |current| return current;
        args.current = args.it.next();
        return args.current;
    }

    pub fn next(args: *Args) ?[:0]const u8 {
        if (args.current) |current| {
            args.current = null;
            return current;
        }
        return args.it.next();
    }

    /// Returns true if there are more flags to parse,
    /// false if there are no more arguments, or the next
    /// argument is "--" or doesn't start with "-"
    pub fn moreFlags(args: *Args) bool {
        const arg = args.peek() orelse {
            log.debug("{s}: no more arguments", .{@src().fn_name});
            return false;
        };
        log.debug("{s}: argument '{s}'", .{ @src().fn_name, arg });
        if (!std.mem.startsWith(u8, arg, "-")) return false;
        if (std.mem.eql(u8, arg, "--")) {
            _ = args.next(); // Consume the "--"
            return false;
        }
        args.help_text.sections.clearRetainingCapacity();

        return true;
    }

    /// Exits with `zflagz.fatal`
    pub fn unknown(args: *Args) noreturn {
        fatal("unknown argument: {s}", .{args.peek().?});
    }

    /// Checks if the current argument is "--help" or "-h"
    pub fn help(args: *Args) bool {
        const current = args.peek() orelse return false;
        if (mem.eql(u8, current, "--help") or mem.eql(u8, current, "-h")) {
            _ = args.next();
            return true;
        }

        return false;
    }

    pub fn exitHelp(args: *Args, status: u8) noreturn {
        std.debug.print("{f}", .{args.help_text});
        std.process.exit(status);
    }

    /// Parses an option with a parameter from the current (and possibly subsequent) argument(s).
    /// Returns `null` if the argument doesn't match, or the parameter value on success.
    /// Crashes with `zflagz.fatal` and an error message if the argument matches, but is missing its parameter,
    /// Supports both `--name <value>` and `--name=<value>` forms.
    pub fn option(args: *Args, name: []const u8, short_name: ?[]const u8, value_syntax: []const u8, description: []const u8) ?[:0]const u8 {
        args.help_text.addSection(args.gpa, .{
            .option = .{
                .name = name,
                .short_name = short_name,
                .value_syntax = value_syntax,
                .description = description,
            },
        }) catch @panic("OOM");
        const current = args.peek() orelse return null;

        if (!mem.startsWith(u8, current, "--")) return null;

        const arg_name = current["--".len..];
        if (mem.eql(u8, arg_name, name)) {
            _ = args.next();
            const value = args.next() orelse fatal("missing argument for --{s}", .{name});
            // Dissallow values starting with "-". They must be passed using `--name=--value`
            if (mem.startsWith(u8, value, "-")) fatal("missing argument for --{s}", .{name});
            return value;
        } else if (arg_name.len > name.len and mem.startsWith(u8, arg_name, name) and arg_name[name.len] == '=') {
            _ = args.next();
            // Allows '--name=', which would mean the value of `name` is the empty string
            return arg_name[name.len + 1 .. :0];
        }

        return null;
    }

    /// Parses a flag from the current argument.
    /// Returns `true` if the argument matches `--[name]`, `false` if it matches `--no-[name]`, and `null` if it doesn't match.
    pub fn flag(args: *Args, name: []const u8, short_name: ?[]const u8, description: []const u8) ?bool {
        args.help_text.addSection(args.gpa, .{
            .flag = .{
                .name = name,
                .short_name = short_name,
                .description = description,
            },
        }) catch @panic("OOM");

        const current = args.peek() orelse return null;
        if (mem.startsWith(u8, current, "--") and mem.eql(u8, current["--".len..], name)) {
            _ = args.next();
            return true;
        } else if (mem.startsWith(u8, current, "--no-") and mem.eql(u8, current["--no-".len..], name)) {
            _ = args.next();
            return false;
        }

        return null;
    }

    pub fn setDescription(args: *Args, description: []const u8) void {
        args.help_text.description = description;
    }
};

pub const HelpText = struct {
    description: []const u8 = "",
    sections: std.ArrayList(Section),

    pub const init: HelpText = .{
        .sections = .empty,
    };

    pub const Section = union(enum) {
        text: []const u8,
        option: struct {
            name: []const u8,
            short_name: ?[]const u8,
            value_syntax: []const u8,
            description: []const u8,
        },
        flag: struct {
            name: []const u8,
            short_name: ?[]const u8,
            description: []const u8,
        },
    };

    pub fn deinit(ht: HelpText, gpa: mem.Allocator) void {
        ht.sections.deinit(gpa);
    }

    pub fn addSection(ht: *HelpText, gpa: mem.Allocator, section: Section) mem.Allocator.Error!void {
        try ht.sections.append(gpa, section);
    }

    pub fn format(
        ht: HelpText,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        // TODO: Usage/synopsis

        try writer.writeAll(ht.description);
        try writer.writeAll("\n\n");

        try writer.writeAll("Options:\n");
        for (ht.sections.items) |section| {
            switch (section) {
                .text => |text| {
                    try writer.writeAll(text);
                    try writer.writeByte('\n');
                },
                .option => |option| {
                    if (option.short_name) |short_name| {
                        try writer.print("  -{s} {s}\n", .{ short_name, option.value_syntax });
                    }
                    try writer.print("  --{s}={s}\n", .{ option.name, option.value_syntax });
                    var line_start: usize = 0;
                    while (std.mem.indexOfPos(u8, option.description, line_start, "\n")) |line_end| : (line_start = line_end + 1) {
                        try writer.print("    {s}\n", .{option.description[line_start..line_end]});
                    }
                    try writer.print("    {s}\n\n", .{option.description[line_start..]});
                },
                .flag => |flag| {
                    if (flag.short_name) |short_name| {
                        try writer.print("  -{s}\n", .{short_name});
                    }
                    try writer.print("  --{s}\n", .{flag.name});
                    var line_start: usize = 0;
                    while (std.mem.indexOfPos(u8, flag.description, line_start, "\n")) |line_end| : (line_start = line_end + 1) {
                        try writer.print("    {s}\n", .{flag.description[line_start..line_end]});
                    }
                    try writer.print("    {s}\n\n", .{flag.description[line_start..]});
                },
            }
        }
    }
};

/// Prints an error message an exits with a non-zero status code
pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("error: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}
