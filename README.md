# LLM Chat

LLM Chat is an efficient chat application that interfaces with various Language Model providers. It features a lightweight GUI and leverages the `zai` library for LLM interactions.

## Features

- GUI built with WebUI, using vanilla JS/HTML/CSS
- Supports multiple LLM providers (OpenAI, TogetherAI, OctoAI, OpenRouter)
- Customizable model parameters (temperature, top_p, frequency_penalty, presence_penalty, max_tokens)
- Efficient state management in Zig
- Streaming responses from LLMs
- Copy-to-clipboard functionality for messages
- Scrollable chat history with arrow key navigation
- Real-time model switching without restarting the application
- Error handling and user-friendly error messages

## Dependencies

- [zig-webui](https://github.com/webui-dev/zig-webui): For creating the GUI
- [zai](https://github.com/AdjectiveAllison/zai): Custom library for LLM provider interactions

## Building and Running

### Interactive Mode
```
zig build run
```

### Install
```
zig build install -Doptimize=ReleaseFast --prefix ~/.local
```

### Build and Run Manually
```
zig build
zig-out/bin/llm-chat
```

## Environment Variables

To use different LLM providers, set the following environment variables:

- OpenAI: `OPENAI_API_KEY`
- TogetherAI: `TOGETHER_API_KEY`
- OctoAI: `OCTOAI_API_KEY`
- OpenRouter: `OPENROUTER_API_KEY`

## Technical Details

- All state and application logic reside in the Zig codebase, with HTML/JS/CSS as a frontend wrapper.
- The binary is small, using the system's installed web browser or webview.
- Implements a chat completion API with streaming support.
- Uses a general-purpose allocator for memory management.
- Implements custom error handling and propagation.

## Future Plans

- Expand to include a CLI version with optional WebUI
- Incorporate retrieval elements
- Add local file editing features

## Contributing

Issues and pull requests are welcome! Feel free to contribute to the project.

## License

This project is licensed under the MIT License.

## Final Thoughts

The tech stack (Zig + WebUI + zai) provides a robust and efficient foundation for building LLM-powered applications. It combines Zig's performance and safety with web technologies' flexibility, making it an excellent choice for cross-platform GUI applications with LLM capabilities.
