const std = @import("std");
const net = std.net;
const tuile = @import("tuile");

const ChatUI = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ChatUI {
        return ChatUI{
            .allocator = allocator,
            .messages = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ChatUI) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg);
        }
        self.messages.deinit();
    }

    pub fn addMessage(self: *ChatUI, message: []const u8) !void {
        try self.messages.append(std.mem.dupe(self.allocator, u8, message));
    }

    pub fn render(self: *ChatUI, tui: *tuile.Tuile) void {
        var list = tui.list();
        for (self.messages.items) |msg| {
            list.itemText(msg);
        }
    }
};

const SERVER = "irc.chat.twitch.tv";
const PORT = 6667;
const CHANNEL = "#theprimeagen";
const OAUTH_TOKEN = "oauth:anonymouse";
const USERNAME = "justinfan12345";

pub fn formatChat(message: []u8) []u8 {
    var username_iter = std.mem.splitScalar(u8, message, '!');
    var unformatted_username = username_iter.next() orelse "";
    if (unformatted_username.len == 0) return "";
    username_iter = std.mem.splitScalar(u8, unformatted_username, ' ');
    _ = username_iter.next().?;

    unformatted_username = username_iter.next() orelse "";
    if (unformatted_username.len == 0) return "";
    const formatted_username = std.mem.trimLeft(u8, unformatted_username, ":");

    var message_iter = std.mem.splitSequence(u8, message, CHANNEL ++ " :");
    _ = message_iter.next().?;
    const formatted_message = message_iter.rest();
    if (formatted_message.len == 0) return "";

    return std.fmt.allocPrint(std.heap.page_allocator, "{s}: {s}\n", .{ formatted_username, formatted_message }) catch "";
}

pub fn getChat(chat_ui: *ChatUI, tui: *tuile.Tuile) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var conn = try std.net.tcpConnectToHost(allocator, SERVER, PORT);
    defer conn.close();

    const writer = conn.writer();
    const reader = conn.reader();

    try writer.print("PASS {s}\r\n", .{OAUTH_TOKEN});
    try writer.print("NICK {s}\r\n", .{USERNAME});
    try writer.print("JOIN {s}\r\n", .{CHANNEL});
    try writer.print("CAP REQ :twitch.tv/tags\r\n", .{});

    var buffer: [1024]u8 = undefined;

    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;

        const message = buffer[0..bytes_read];

        if (std.mem.startsWith(u8, message, "PING")) {
            try writer.print("PONG :tmi.twitch.tv\r\n", .{});
        }

        if (std.mem.indexOf(u8, message, "PRIVMSG") != null and
            (std.mem.indexOf(u8, message, "mod=1") != null or
            std.mem.indexOf(u8, message, "vip=1") != null))
        {
            const output_message = formatChat(message);
            if (output_message.len > 0) {
                tui.scheduleTask(struct {
                    fn task(ctx: *anyopaque) void {
                        const chat = @as(*ChatUI, @ptrCast(ctx));
                        chat.addMessage(output_message) catch return;
                    }
                }.task, &chat_ui);
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var tui = try tuile.Tuile.init(.{});
    defer tui.deinit();

    var chat_ui = ChatUI.init(allocator);
    defer chat_ui.deinit();

    try tui.add(
        tuile.block(
            .{
                .border = tuile.Border.all(),
                .border_type = .rounded,
                .layout = .{ .flex = 1 },
            },
            chat_ui.render(&tui),
        ),
    );

    // Spawn a thread to listen for chat messages
    _ = try std.Thread.spawn(.{}, getChat, .{ &chat_ui, &tui });

    try tui.run(); // Properly run the Tuile event loop
}
