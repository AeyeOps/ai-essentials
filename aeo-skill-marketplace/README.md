# AEO Skill Marketplace

Curated collection of AI development skills for Claude Code and compatible agents.

## Installation

### Add the Marketplace

```bash
# From GitHub (after publishing)
/plugin marketplace add AeyeOps/aeo-skill-marketplace

# From local directory
/plugin marketplace add ./aeo-skill-marketplace
```

### Install Plugins

Once the marketplace is added, install individual plugins:

```bash
# Install the Claude Agent SDK skill
/plugin install claude-agent-sdk@aeo-skill-marketplace
```

## Available Plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| [claude-agent-sdk](./claude-agent-sdk) | development | Expert guidance for building autonomous AI agents using Anthropic's Claude Agent SDK (Python) |

## Plugin Details

### claude-agent-sdk

Expert guidance for building autonomous AI agents.

**Covers:**
- Agent loop patterns (GTVR: gather context, take action, verify, repeat)
- `ClaudeSDKClient` and `query()` APIs
- Streaming vs single-mode execution
- Custom tool design with `@tool` decorator
- MCP server integration
- Hooks for runtime control
- Permission models
- Authentication (API key vs subscription OAuth)
- Production deployment patterns

**Triggers when you ask about:**
- Building custom agents with Claude Agent SDK
- Designing effective tools and MCP servers
- Implementing permission models and guardrails
- Configuring authentication
- Creating multi-agent systems

## Adding New Plugins

1. Create a directory at the marketplace root with your plugin name
2. Add `.claude-plugin/plugin.json` with plugin metadata
3. Add your components (skills, commands, agents, hooks)
4. Update `.claude-plugin/marketplace.json` to include your plugin
5. Submit a PR

## Structure

```
aeo-skill-marketplace/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace index
├── README.md
├── LICENSE
└── claude-agent-sdk/             # Plugin: Claude Agent SDK
    ├── .claude-plugin/
    │   └── plugin.json
    └── skills/
        └── claude-agent-sdk/
            ├── SKILL.md
            ├── references/
            └── examples/
```

## License

MIT
