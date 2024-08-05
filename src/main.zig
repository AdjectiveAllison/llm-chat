const std = @import("std");
const zai = @import("zai");
const webui = @import("webui");

const html = @embedFile("index.html");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var ai: zai.AI = undefined;
var message_history: std.ArrayList(zai.Message) = undefined;
var current_provider: zai.Provider = .OctoAI;
var current_model: []u8 = undefined;

pub fn main() !void {
    try ai.init(allocator, current_provider);
    defer ai.deinit();

    message_history = std.ArrayList(zai.Message).init(allocator);
    defer message_history.deinit();

    current_model = try allocator.dupe(u8, "mixtral-8x7b-instruct-fp16");
    defer allocator.free(current_model);

    var win = webui.newWindow();

    _ = win.bind("sendMessageToAI", sendMessageToAI);
    _ = win.bind("clearChatHistory", clearChatHistory);
    _ = win.bind("updateProvider", updateProvider);
    _ = win.bind("updateModel", updateModel);
    _ = win.show(html);

    webui.wait();
}

fn sendMessageToAI(e: webui.Event) void {
    const message = e.getString();

    message_history.append(.{ .role = "user", .content = message }) catch |err| {
        std.debug.print("Error appending user message: {}\n", .{err});
        showErrorToUser(e, "Failed to process user message");
        return;
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(allocator);
    defer chat_completion.deinit();

    const payload = zai.CompletionPayload{
        .model = current_model,
        .messages = message_history.items,
        .temperature = 0.7,
        .stream = true,
    };

    const user_writer = zai.ChatCompletion.UserWriter{
        .context = @ptrCast(@alignCast(@constCast(&e))),
        .write_fn = writeToWindow,
    };

    e.runClient("startNewAIMessage()");

    chat_completion.requestStream(&ai, payload, user_writer) catch |err| {
        std.debug.print("Error in chat completion: {}\n", .{err});
        showErrorToUser(e, "Failed to get AI response");
        return;
    };

    const ai_response = allocator.dupe(u8, chat_completion.content.items) catch |err| {
        std.debug.print("Error duplicating AI response: {}\n", .{err});
        showErrorToUser(e, "Failed to process AI response");
        return;
    };

    message_history.append(.{ .role = "assistant", .content = ai_response }) catch |err| {
        std.debug.print("Error appending AI response to history: {}\n", .{err});
        allocator.free(ai_response);
        showErrorToUser(e, "Failed to save AI response");
        return;
    };

    e.runClient("endAIMessage()");
}

fn updateProvider(e: webui.Event) void {
    const provider_str = e.getString();
    const new_provider = std.meta.stringToEnum(zai.Provider, provider_str) orelse {
        std.debug.print("Invalid provider: {s}\n", .{provider_str});
        showErrorToUser(e, "Invalid provider selected");
        return;
    };

    if (new_provider != current_provider) {
        ai.deinit();
        current_provider = new_provider;
        ai.init(allocator, current_provider) catch |err| {
            std.debug.print("Error initializing new provider: {}\n", .{err});
            showErrorToUser(e, "Failed to initialize new provider");
            return;
        };
    }
}

fn updateModel(e: webui.Event) void {
    const new_model = e.getString();
    allocator.free(current_model);
    current_model = allocator.dupe(u8, new_model) catch |err| {
        std.debug.print("Error updating model: {}\n", .{err});
        showErrorToUser(e, "Failed to update model");
        return;
    };
}

fn showErrorToUser(e: webui.Event, message: []const u8) void {
    const error_script = std.fmt.allocPrintZ(allocator, "showError('{s}');", .{message}) catch |err| {
        std.debug.print("Error allocating error message: {}\n", .{err});
        return;
    };
    defer allocator.free(error_script);
    e.runClient(error_script);
}

fn writeToWindow(context: ?*anyopaque, content: []const u8) !void {
    const event: *const webui.Event = @ptrCast(@alignCast(context.?));
    const escaped_content = try std.json.stringifyAlloc(allocator, content, .{});
    defer allocator.free(escaped_content);

    // Append to the current AI message
    const script = try std.fmt.allocPrintZ(allocator, "appendToAIMessage({s})", .{escaped_content});
    defer allocator.free(script);

    event.runClient(script);
}

fn clearChatHistory(e: webui.Event) void {
    message_history.clearRetainingCapacity();
    e.runClient("clearChatUI()");
}
