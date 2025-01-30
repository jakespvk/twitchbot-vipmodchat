const std = @import("std");
const net = std.net;

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

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var conn = try net.tcpConnectToHost(allocator, SERVER, PORT);
    defer conn.close();
    try stdout.writeAll("Made connection\n\n");

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
        //try stdout.print("{s}\n", .{message});
        if (std.mem.startsWith(u8, message, "PING")) {
            try writer.print("PONG :tmi.twitch.tv\r\n", .{});
        }

        if (std.mem.indexOf(u8, message, "PRIVMSG") != null) {
            if (std.mem.indexOf(u8, message, "mod=1") != null or
                std.mem.indexOf(u8, message, "vip=1") != null)
            {
                // try stdout.print("{s}\n", .{message});
                const output_message = formatChat(message);

                if (std.mem.indexOf(u8, output_message, "nightbot") != null or
                    std.mem.indexOf(u8, output_message, "Cheer") != null or
                    std.mem.indexOf(u8, output_message, "cheer") != null)
                {
                    continue;
                } else {
                    try stdout.print("{s}", .{output_message});
                }
            }
        }
    }
}
