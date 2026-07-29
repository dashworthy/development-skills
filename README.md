# Dashworthy Development Skills

A Claude Code **plugin marketplace** — a growing collection of independently-installable plugins, published from this one repo.

Each plugin here is self-contained. They share an author and a marketplace, not a dependency: install one, install several, or install none. Adding the marketplace does not install anything.

## Add the marketplace

```
/plugin marketplace add https://github.com/dashworthy/development-skills
```

Then install whichever plugins you want:

```
/plugin install signal@dashworthy
/plugin install verity@dashworthy
```

## Plugins

| Plugin | What it does | How you invoke it |
|---|---|---|
| **[signal](signal/README.md)** `0.1.0` | Discovery. Interrogates a vague request into hard requirements, surfaces what you didn't think to ask for, and orders the result into a brief where nothing appears before what it depends on. It produces a brief and stops — it does not design, plan, or build. | `/signal <request>` |
| **[verity](verity/README.md)** `0.1.0` | Diff-scoped test hardening. Audits a branch diff for weakly-tested behaviour, writes tests and only tests to close the gaps, and verifies those tests actually assert what they claim — looping until thresholds are met or it runs out of road. Never modifies application code. | No command — invoke the `conducting-test-hardening` skill, or let it fire when implementation work finishes |

They are not sequential stages of one tool, but they do sit at opposite ends of the same piece of work: signal runs before anything is built, when the question is *what are we actually making?* Verity runs after, when the question is *would anything notice if this broke?* Neither knows about the other, and neither needs the other installed.

Each plugin's own README carries its process-flow diagram and — in both cases — an explicit account of what it does **not** guarantee: [signal](signal/README.md#the-two-stages), [verity](verity/README.md#how-a-run-flows).



## Repository layout

```
development-skills/
├── .claude-plugin/marketplace.json   the dashworthy marketplace
├── signal/                           one plugin
│   └── .claude-plugin/plugin.json
└── verity/                           another
    └── .claude-plugin/plugin.json
```

A new plugin is a new top-level directory with its own `.claude-plugin/plugin.json`, plus an entry in the marketplace manifest. Nothing inside the existing plugins changes when one is added.

## License

MIT. See [LICENSE](LICENSE).
