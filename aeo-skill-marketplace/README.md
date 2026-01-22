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
# Install a specific plugin
/plugin install aeo-architecture@aeo-skill-marketplace
```

## Available Plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| [claude-agent-sdk](./claude-agent-sdk) | development | Expert guidance for building autonomous AI agents using Anthropic's Claude Agent SDK |
| [aeo-agile-tools](./aeo-agile-tools) | productivity | Agile team roles: Scrum Master, Product Owner, Business Analyst, and Project Manager agents |
| [aeo-architecture](./aeo-architecture) | development | Architecture design with 10 specialized agents for C4 diagrams, ADRs, and quality analysis |
| [aeo-code-analysis](./aeo-code-analysis) | development | Code archaeology and technology evaluation for legacy systems and technical debt |
| [aeo-deployment](./aeo-deployment) | deployment | Deployment orchestration and compliance automation with progressive rollout strategies |
| [aeo-documentation](./aeo-documentation) | development | Complete Diataxis documentation framework with 12 specialized agents |
| [aeo-epcc-workflow](./aeo-epcc-workflow) | development | EPCC (Explore-Plan-Code-Commit) systematic development workflow |
| [aeo-performance](./aeo-performance) | development | Performance profiling, optimization, and monitoring with 5 specialized agents |
| [aeo-requirements](./aeo-requirements) | productivity | Product and technical requirements gathering with technology evaluation guidance |
| [aeo-security](./aeo-security) | security | Security scanning, auditing, and compliance validation with 4 specialized agents |
| [aeo-tdd-workflow](./aeo-tdd-workflow) | testing | TDD workflow with 6 specialized agents for test-first development |
| [aeo-testing](./aeo-testing) | testing | Testing, QA, and quality gates with 3 specialized agents |
| [aeo-troubleshooting](./aeo-troubleshooting) | development | Systematic debugging and problem-solving with ask-for-help mechanism |
| [aeo-ux-design](./aeo-ux-design) | design | UX optimization and UI design tools with accessibility validation |

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
├── claude-agent-sdk/             # Plugin: Claude Agent SDK
├── aeo-agile-tools/              # Plugin: Agile Tools
├── aeo-architecture/             # Plugin: Architecture
├── aeo-code-analysis/            # Plugin: Code Analysis
├── aeo-deployment/               # Plugin: Deployment
├── aeo-documentation/            # Plugin: Documentation
├── aeo-epcc-workflow/            # Plugin: EPCC Workflow
├── aeo-performance/              # Plugin: Performance
├── aeo-requirements/             # Plugin: Requirements
├── aeo-security/                 # Plugin: Security
├── aeo-tdd-workflow/             # Plugin: TDD Workflow
├── aeo-testing/                  # Plugin: Testing
├── aeo-troubleshooting/          # Plugin: Troubleshooting
└── aeo-ux-design/                # Plugin: UX Design
```

## License

MIT
