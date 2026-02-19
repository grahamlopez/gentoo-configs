
# AGENTS.md – Linux Boot Project

## Goal
Completely optimized boot process for Gentoo Linux systems that is as optimized
as possible in each of the following ways:
- minimal: customized linux kernel build, initrd, firmware, and userspace boot
- fast: optimized boot including kernel and user space startup
- security: full luks encryption with multiple decrypt methods, secure boot, etc.

## Environment
- Distro + version: Gentoo Linux using the systemd/desktop profile
- Kernel version(s): 6.12 with the patchset from the `gentoo-sources` package
- Desktop environment / WM: Wayland + Hyprland
- Machine model / CPU / GPU:
- Where configs live: /etc, /lib, /usr/src/linux, /boot
- How I apply changes: manual file editing

## Capabilities & Limits
- You can:
  - Propose shell commands, sysctl settings, service changes, config file edits, and how to gather diagnostic information.
  - Suggest packages to install or remove.
  - Suggest changes to the kernel `.config`, bios configuration, initrd construction, or firmware loading.
  - Help interpret logs and command outputs I paste.
- You must NOT:
  - Suggest destructive commands (rm -rf /, writing to random block devices, etc.).
  - Make suggestions that you are unsure of or make haphazard guesses.

## Safety Rules
- Prefer read/inspect commands first (cat, systemctl status, journalctl, ls) before writes.
- When suggesting commands:
  - Label them clearly with intent, e.g. `# inspect`, `# apply`, `# revert`.
  - Default to the least invasive option.
- Always propose a quick rollback step for any change (e.g. how to undo a sysctl, restore a config backup, disable a service).
- Warn when you suspect that a suggestion or procedure could cause the system to become unbootable or otherwise degraded.

## Project Structure
- `/plans/` – Plan files for individual experiments or tasks.
- `/notes/` – Raw logs, experiment results, snapshots.
- `/configs/` – Canonical config files or templates.
- `/docs/` – Finished howto documentation on completed tasks
- `PROJECT.md` – High-level goals and roadmap (human-facing).

## Workflows
- **Before suggesting or changing anything**
  - Ask clarifying questions if needed.
  - Confirm the current target plan (which `PLAN-*.md` we are working on).
- **When proposing changes**
  - Ensure the suggestion is backed up by documentation or referenced expert knowledge of best practices.
  - Work in small steps; list commands in the order they should be run.
  - After each step, tell me exactly what output/logs to capture and paste back, and what the expected output is.
- **Debugging**
  - Ask for relevant logs or command outputs and how to get them; don’t guess blindly.
  - When something fails, propose a minimal “triage checklist” first.

## Style
- Use concise bullet lists for commands and steps.
- Make hypotheses explicit: “Hypothesis: …; To test it: …”.
- Include a description of the source that backs up the suggestion; otherwise indicate when suggestions do not have an obvious basis in documentation or discovered expert knowledge.
- At the end of each interaction, include:
  - A one-paragraph state summary.
  - A short TODO list for next time.
