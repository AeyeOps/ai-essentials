# Claude Agent SDK Plugin

Expert guidance for building autonomous AI agents using Anthropic's Claude Agent SDK (Python).

## Installation

```bash
# If marketplace is already added
/plugin install claude-agent-sdk@aeo-skill-marketplace

# Or load directly
claude --plugin-dir ./claude-agent-sdk
```

## What's Included

### Skill: claude-agent-sdk

Comprehensive guidance covering:

- **Agent Loop Patterns** - GTVR: gather context, take action, verify, repeat
- **Core APIs** - `ClaudeSDKClient` and `query()` usage
- **Streaming** - Real-time vs single-mode execution
- **Custom Tools** - `@tool` decorator and MCP server integration
- **Hooks** - Runtime control and validation
- **Permissions** - Security models and guardrails
- **Authentication** - API key vs subscription OAuth, token lifecycle
- **Production** - Deployment patterns and best practices

### Reference Documentation

| File | Topic |
|------|-------|
| `references/python-sdk.md` | Complete Python API reference |
| `references/streaming.md` | Streaming vs single mode patterns |
| `references/tools-mcp.md` | Tool design and MCP integration |
| `references/authentication.md` | Auth patterns and token lifecycle |
| `references/architecture-patterns.md` | GTVR, orchestration, production |

### Examples

| File | Description |
|------|-------------|
| `examples/basic_query.py` | Simplest working agent |
| `examples/custom_tools.py` | Custom MCP tools with `@tool` |
| `examples/stateful_client.py` | Production patterns with hooks |
| `examples/extended_thinking.py` | Extended thinking mode |
| `examples/streaming_events.py` | Real-time streaming |

All examples require `claude-agent-sdk>=0.1.20` and the Claude Code CLI.

## Trigger Phrases

The skill activates when you ask about:

- Building custom agents with Claude Agent SDK
- Designing effective tools and MCP servers
- Implementing permission models and guardrails
- Configuring authentication (API key or subscription)
- Creating multi-agent orchestration systems
- Deploying agents to production

## License

MIT
