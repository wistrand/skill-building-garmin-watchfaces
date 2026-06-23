# building-garmin-watchfaces

A [Claude Agent Skill](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) for building Garmin Connect IQ watch faces in Monkey C. It captures the parts that tend to cost hours: device capability surprises, always-on (AOD) and sleep correctness, the per-frame budget, cross-device font sizing, and the settings pipeline.

The guidance is distilled from building a real AMOLED analog face (moon/sun ephemeris, radial text, cached buffers). It assumes Monkey C and Connect IQ basics and only documents the non-obvious, device-specific parts.

## What's inside

- `SKILL.md` — the skill: when-to-use metadata, three workflows (scaffold, vet a device, debug AOD/sleep), and links to the reference files.
- `reference/` — load-on-demand detail: [toolchain](reference/toolchain.md), [device capabilities](reference/device-capabilities.md), [AOD and sleep](reference/aod-and-sleep.md), [performance](reference/performance.md), [fonts](reference/fonts.md), [settings](reference/settings.md).
- `scripts/`
  - `vet-device.py` — report a device's display / API / graphics-pool / colour / **vector-font** support and assert requirements. Stdlib only.
  - `new-project.sh` — scaffold a minimal buildable watch-face project.
  - `shot.sh` — build, load into the simulator, and screenshot the window.

## Install

### As a personal skill (your own machine)

Clone anywhere and symlink it into your Claude Code skills directory so the repo stays the source of truth:

```bash
git clone <repo-url> ~/src/building-garmin-watchfaces
ln -s ~/src/building-garmin-watchfaces ~/.claude/skills/building-garmin-watchfaces
```

Claude Code then discovers it; invoke with `/building-garmin-watchfaces` or let it trigger from a matching request. The symlink name sets the command name.

### As a Claude Code plugin (sharing with others)

The repo carries a `.claude-plugin/plugin.json`, so it can also be installed as a plugin via a marketplace pointing at this git repo. See the Claude Code [plugins docs](https://code.claude.com/docs/en/plugins).

Use one install path at a time on a given machine, not both, to avoid a name clash.

## Using the scripts standalone

The scripts work without Claude Code, given the Connect IQ toolchain:

```bash
# does this device support a radial-text + cached-buffer design?
scripts/vet-device.py venu2 --need vector-fonts graphics-pool

# scaffold and run a new face
scripts/new-project.sh Moonphase marq2aviator ./moonphase
```

## License

MIT. See [LICENSE](LICENSE).
