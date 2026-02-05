const std = @import("std");
const Io = std.Io;

const zflagz = @import("zflagz");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var it = try init.minimal.args.iterateAllocator(gpa);
    _ = it.skip();
    const cmd: Command = .parse(gpa, &it);
    _ = cmd;
}

const Command = struct {
    all: bool,
    patch: bool,
    /// --reuse-message/--reedit-message
    reuse_reedit_message: union(enum) {
        no,
        reuse: []const u8,
        reedit: []const u8,
    },
    fixup: union(enum) {
        no,
        fixup: []const u8,
        amend: []const u8,
        reword: []const u8,
    },
    squash: ?[]const u8,
    reset_author: bool,
    short: bool,
    branch: bool,
    porcelain: bool,
    long: bool,
    znull: bool,
    file: ?[]const u8,
    author: ?[]const u8,
    date: ?[]const u8,
    message: ?[]const u8,
    template: ?[]const u8,
    signoff: bool,
    trailer: ?struct {
        token: []const u8,
        value: ?[]const u8,
    },
    verify: bool,
    allow_empty: bool,
    allow_empty_message: bool,
    cleanup: enum { strip, whitespace, verbatim, scissors, default },
    // --edit/--no-edit
    edit: bool,
    amend: bool,
    include: bool,
    only: bool,
    pathspec_from_file: ?[]const u8,
    pathspec_file_nul: bool,
    /// --untracked-files[=<mode>]
    // NOTE: Can't do optional <mode>
    untracked_files: enum { no, normal, all },
    verbose: u32,
    quiet: bool,
    dry_run: bool,
    status: bool,
    /// --gpg-sign[=<key-id>]
    // NOTE: Can't do optional <key-id>
    gpg_sign: ?[]const u8,

    pub fn parse(gpa: std.mem.Allocator, it: *std.process.Args.Iterator) Command {
        var all = false;
        var patch = false;
        var reuse_reedit_message: @FieldType(Command, "reuse_reedit_message") = .no;
        var fixup: @FieldType(Command, "fixup") = .no;
        var squash: ?[]const u8 = null;
        // var reset_author = false;
        // var short = false;
        // var branch = false;
        // var porcelain = false;
        // var long = false;
        // var znull = false;
        // var file: ?[]const u8 = null;
        // var author: ?[]const u8 = null;
        // var date: ?[]const u8 = null;
        // var message: ?[]const u8 = null;
        // var template: ?[]const u8 = null;
        // var signoff = false;
        // var trailer: @FieldType(Command, "trailer") = null;
        // var verify = false;
        // var allow_empty = false;
        // var allow_empty_message = false;
        // var cleanup: @FieldType(Command, "cleanup") = .default;
        // var edit = false;
        // var amend = false;
        // var include = false;
        // var only = false;
        // var pathspec_from_file: ?[]const u8 = null;
        // var pathspec_file_nul = false;
        // var untracked_files: @FieldType(Command, "untracked_files") = .no;
        // var verbose: u32 = 0;
        // var quiet = false;
        // var dry_run = false;
        // var status = false;
        // // NOTE: Can't do optional <key-id>
        // var gpg_sign: ?[]const u8 = null;

        var args: zflagz.Args = .init(gpa, it);

        args.setDescription(
            \\Commit some files, idk...
        );

        while (args.moreFlags()) {
            if (args.flag("all", "a",
                \\Automatically stage files that have been modified and deleted, but new
                \\files you have not told Git about are not affected.
            )) |all_flag| {
                all = all_flag;
            } else if (args.flag("patch", "p",
                \\Use the interactive patch selection interface to choose which changes
                \\to commit. See git-add(1) for details.
            )) |patch_flag| {
                patch = patch_flag;
            } else if (args.option("reuse-message", "C", "<commit>",
                \\Take an existing <commit> object, and reuse the log message and the
                \\authorship information (including the timestamp) when creating the commit.
            )) |reuse_message_opt| {
                reuse_reedit_message = .{
                    .reuse = reuse_message_opt,
                };
            } else if (args.option("reedit-message", "c", "<commit>",
                \\Like -C, but with -c the editor is invoked, so that the user can
                \\further edit the commit message.
            )) |reedit_message_opt| {
                reuse_reedit_message = .{
                    .reedit = reedit_message_opt,
                };
            } else if (args.option("fixup", null, "[(amend|reword):]<commit>",
                \\Create a new commit which "fixes up" <commit> when applied with git
                \\rebase --autosquash. Plain --fixup=<commit> creates a "fixup!" commit
                \\which changes the content of <commit> but leaves its log message
                \\untouched. --fixup=amend:<commit> is similar but creates an "amend!"
                \\commit which also replaces the log message of <commit> with the log
                \\message of the "amend!" commit. --fixup=reword:<commit> creates an
                \\"amend!" commit which replaces the log message of <commit> with its
                \\own log message but makes no changes to the content of <commit>.
            )) |fixup_opt| {
                if (std.mem.startsWith(u8, fixup_opt, "amend:")) {
                    fixup = .{
                        .amend = fixup_opt["amend:".len..],
                    };
                } else if (std.mem.startsWith(u8, fixup_opt, "reword:")) {
                    fixup = .{
                        .reword = fixup_opt["reword:".len..],
                    };
                } else {
                    fixup = .{
                        .fixup = fixup_opt,
                    };
                }
            } else if (args.option("squash", null, "<commit>",
                \\Construct a commit message for use with git rebase --autosquash. The
                \\commit message title is taken from the specified commit with a prefix
                \\of "squash! ". Can be used with additional commit message options (-m/-c/-C/-F).
                \\See git-rebase(1) for details.
            )) |squash_opt| {
                squash = squash_opt;
            } else if (args.help()) {
                args.exitHelp(0);
            } else {
                args.unknown();
            }
        }

        std.debug.print("Command(all: {}, patch: {}, reuse_reedit_message: ", .{ all, patch });
        switch (reuse_reedit_message) {
            .no => std.debug.print("no", .{}),
            .reuse => |commit| std.debug.print("reuse='{s}'", .{commit}),
            .reedit => |commit| std.debug.print("reedit='{s}'", .{commit}),
        }
        std.debug.print(", fixup: ", .{});
        switch (fixup) {
            .no => std.debug.print("no", .{}),
            .fixup => |commit| std.debug.print("fixup='{s}'", .{commit}),
            .amend => |commit| std.debug.print("amend='{s}'", .{commit}),
            .reword => |commit| std.debug.print("reword='{s}'", .{commit}),
        }
        if (squash) |s| {
            std.debug.print(", squash: '{s}'", .{s});
        } else {
            std.debug.print(", squash: null", .{});
        }
        std.debug.print(")\n", .{});
        zflagz.fatal("TODO: implement the rest", .{});
    }
};
