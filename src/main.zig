const std = @import("std");
const zai = @import("zai");
const webui = @import("webui");

const html = @embedFile("index.html");

// Global state
const State = struct {
    allocator: std.mem.Allocator,
    ai: zai.AI,
    message_history: std.ArrayList(zai.Message),
    current_provider: zai.Provider,
    current_model: []u8,

    fn init(allocator: std.mem.Allocator) !State {
        return State{
            .allocator = allocator,
            .ai = undefined, // We'll initialize this separately
            .message_history = std.ArrayList(zai.Message).init(allocator),
            .current_provider = .OctoAI,
            .current_model = try allocator.dupe(u8, "mixtral-8x7b-instruct-fp16"),
        };
    }

    fn deinit(self: *State) void {
        self.message_history.deinit();
        self.allocator.free(self.current_model);
        self.ai.deinit();
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var state: State = undefined;

pub fn main() !void {
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    state = try State.init(allocator);
    defer state.deinit();

    try initializeAI();

    var win = webui.newWindow();

    try bindFunctions(&win);
    _ = win.show(html);

    webui.wait();
}

fn initializeAI() !void {
    std.log.info("Initializing AI with provider: {s}", .{@tagName(state.current_provider)});
    try state.ai.init(state.allocator, state.current_provider);
}

fn bindFunctions(win: *webui) !void {
    _ = win.bind("sendMessageToAI", sendMessageToAI);
    _ = win.bind("clearChatHistory", clearChatHistory);
    _ = win.bind("updateAIProvider", updateAIProvider);
    _ = win.bind("updateAIModel", updateAIModel);
}

fn sendMessageToAI(e: webui.Event) void {
    const raw_message = e.getString();
    const message = std.mem.sliceTo(raw_message, 0); // This will stop at the null terminator
    std.log.info("Received message: {s}", .{message});

    state.message_history.append(.{ .role = "user", .content = message }) catch |err| {
        std.log.err("Error appending user message: {}", .{err});
        showErrorToUser(e, "Failed to process user message");
        return;
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(state.allocator);
    defer chat_completion.deinit();

    const payload = zai.CompletionPayload{
        .model = state.current_model,
        .messages = state.message_history.items,
        .temperature = 0.7,
        .stream = true,
    };

    std.log.info("Sending request with model: {s}", .{state.current_model});
    const user_writer = zai.ChatCompletion.UserWriter{
        .context = @ptrCast(@alignCast(@constCast(&e))),
        .write_fn = writeToWindow,
    };

    e.runClient("startNewAIMessage()");

    std.debug.print("Payload: {any}\n", .{payload});
    chat_completion.requestStream(&state.ai, payload, user_writer) catch |err| {
        std.log.err("Error in chat completion: {}", .{err});
        const error_message = switch (err) {
            zai.AI.AIError.HttpRequestFailed => "Failed to connect to the AI service",
            zai.AI.AIError.InvalidResponse => "Received an invalid response from the AI service",
            zai.AI.AIError.UnexpectedStatus => "Unexpected status from the AI service",
            zai.AI.AIError.ApiError => "API error occurred",
            else => "An unknown error occurred",
        };
        showErrorToUser(e, error_message);
        return;
    };

    const ai_response = state.allocator.dupe(u8, chat_completion.content.items) catch |err| {
        std.log.err("Error duplicating AI response: {}", .{err});
        showErrorToUser(e, "Failed to process AI response");
        return;
    };
    defer state.allocator.free(ai_response);

    state.message_history.append(.{ .role = "assistant", .content = ai_response }) catch |err| {
        std.log.err("Error appending AI response to history: {}", .{err});
        showErrorToUser(e, "Failed to save AI response");
        return;
    };

    e.runClient("endAIMessage()");
}

fn updateAIProvider(e: webui.Event) void {
    const raw_provider_str = e.getString();
    const provider_str = std.mem.sliceTo(raw_provider_str, 0);
    std.log.info("Updating provider to: {s}", .{provider_str});

    const new_provider = std.meta.stringToEnum(zai.Provider, provider_str) orelse {
        std.log.err("Invalid provider: {s}", .{provider_str});
        showErrorToUser(e, "Invalid provider selected");
        return;
    };

    if (new_provider != state.current_provider) {
        state.ai.deinit();
        state.current_provider = new_provider;
        initializeAI() catch |err| {
            std.log.err("Error initializing new provider: {}", .{err});
            showErrorToUser(e, "Failed to initialize new provider");
            return;
        };
        std.log.info("Provider updated successfully to: {s}", .{@tagName(state.current_provider)});
    } else {
        std.log.info("Provider unchanged: {s}", .{@tagName(state.current_provider)});
    }
}

fn updateAIModel(e: webui.Event) void {
    const new_model = e.getString();
    if (new_model.len == 0) {
        std.log.err("Received empty model string", .{});
        showErrorToUser(e, "Invalid model name");
        return;
    }

    std.log.info("Updating model to: {s}", .{new_model});

    // Allocate new memory for the model name
    const new_model_owned = state.allocator.dupeZ(u8, new_model) catch |err| {
        std.log.err("Error duplicating new model string: {}", .{err});
        showErrorToUser(e, "Failed to update model");
        return;
    };

    // Free the old model name
    state.allocator.free(state.current_model);

    // Update the current model
    state.current_model = new_model_owned;
    std.log.info("Model updated successfully to: {s}", .{state.current_model});
}

fn showErrorToUser(e: webui.Event, message: []const u8) void {
    std.log.err("Showing error to user: {s}", .{message});
    const error_script = std.fmt.allocPrintZ(state.allocator, "showError('{s}');", .{message}) catch |err| {
        std.log.err("Error allocating error message: {}", .{err});
        return;
    };
    defer state.allocator.free(error_script);
    e.runClient(error_script);
}

fn writeToWindow(context: ?*anyopaque, content: []const u8) !void {
    const event: *const webui.Event = @ptrCast(@alignCast(context.?));
    const escaped_content = try std.json.stringifyAlloc(state.allocator, content, .{});
    defer state.allocator.free(escaped_content);

    const script = try std.fmt.allocPrintZ(state.allocator, "appendToAIMessage({s})", .{escaped_content});
    defer state.allocator.free(script);

    event.runClient(script);
}

fn clearChatHistory(e: webui.Event) void {
    std.log.info("Clearing chat history", .{});
    state.message_history.clearRetainingCapacity();
    e.runClient("clearChatUI()");
}
