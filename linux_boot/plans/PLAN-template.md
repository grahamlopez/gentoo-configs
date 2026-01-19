
# PLAN: <topic>

Each PLAN is a tight, single-topic document: one device, one subsystem, or one
experiment (e.g. “boot time”, “power saving”, “audio latency”).

Each PLAN should answer:
- What are we trying to achieve?
- What is the current state?
- What are the next 3–7 concrete steps?

You then:
- Ask Perplexity to draft or refine one plan at a time.
- After running commands and collecting logs, paste results and let the plan be
  updated with “Findings & Decisions” and refined next steps.

When starting a session, you can say something like:

    “We’re working in plans/PLAN-audio-low-latency.md. Here is the current file.
    Help me refine the Experiments section and propose the next three
    experiments given these logs: …”

Good habits:
- Always name the active plan explicitly.
- Keep commands and outputs small and scoped to one experiment.

Ask for:
- “Update the plan given these results.”
- “Trim obsolete experiments and keep only what matters now.”

This keeps context tight and emulates the “plan → execute → test → commit → next
plan” loop described for code projects.

## Objective
- One or two sentences.
- Example: Achieve stable sub-10ms audio latency in JACK/PipeWire with no XRuns
  under normal desktop usage.

## Constraints & Safety
- Acceptable trade-offs (e.g. can increase power use, but not fan noise beyond X).
- Things that must not break (Wi-Fi, suspend/resume, secure boot, etc.).
- Risk tolerance level for this plan (low/medium/high).

## Current State (Snapshot)
- Distro, kernel, relevant packages.
- Key config values already in place (summarized, not full files).
- Known working and broken behaviors.
- Paste links or filenames to detailed notes/logs if needed (e.g.
  `../notes/audio-dmesg-2026-01-18.md`).

## Hypotheses
- H1: <short statement> (e.g. CPU governor is causing underruns).
- H2: ...
- Keep these updated as we learn.

## Experiments / Tasks
- E1: <Title> (e.g. Switch to performance governor during audio sessions)
  - Goal: <what success looks like>.
  - Steps (for the user to run):
    1. Command 1
    2. Command 2
    3. Log collection (which logs/outputs to capture)
  - Expected signals:
    - What “success” output looks like.
    - What “failure” output looks like.
- E2: ...
- Keep this list short and current (you can archive old experiments below).

## Debugging Checklist
- If X happens, run:
  - `command` and paste output.
- If Y happens, check:
  - `journalctl ...`
  - config file path, etc.

## Findings & Decisions
- DD-2026-01-18: <decision> – why it was made.
- Summarize durable choices so we can re-derive them later.

## Open Questions
- List of unresolved questions you want the AI to ask about or help explore.
