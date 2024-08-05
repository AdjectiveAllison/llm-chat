const std = @import("std");
const zai = @import("zai");
const webui = @import("webui");

pub fn main() !void {
    std.debug.print("Hello, world!\n", .{});
    var win = webui.newWindow();
    const index_html = @embedFile("index.html");
    _ = win.show(index_html);

    webui.wait();
}
