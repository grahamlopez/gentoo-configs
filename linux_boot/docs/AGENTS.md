# AGENTS.md – Linux Boot Project Documentation

## Overall Project Goal
Completely optimized boot process for Gentoo Linux systems that is as optimized
as possible in each of the following ways:
- minimal: customized linux kernel build, initrd, firmware, and userspace boot
- fast: optimized boot including kernel time and user space startup time
- security: full luks encryption with multiple decrypt methods, secure boot, etc.

## Documentation Goal
Successfully completed tasks are finalized with user-facing documentation that:
- describes the task with relevant background information
- gives the motivation for and advantages of doing the task
- lists alternative methods and the pros and cons compared to the completed task
- lays out a step by step instructional guide with short explanations
- gives a summary of common pitfalls and how to avoid them

Each documented task should live in its own file or section and follow a consistent structure so users can quickly scan and reuse the pattern.

## Environment
- Distro + version: Gentoo Linux using the systemd/desktop profile
- Kernel version(s): 6.12 with the patchset from the `gentoo-sources` package
- Desktop environment / WM: Wayland + Hyprland
- Machine model / CPU / GPU:
- Where configs live: /etc, /lib, /usr/src/linux, /boot
- How I apply changes: manual file editing

For each task document, explicitly note any deviations from this baseline environment (e.g., different kernel version, different bootloader, virtual machine vs bare metal).

## Capabilities & Limits
- You can:
  - Propose organizational improvements to the documentation.
  - Point out statements that you suspect may not be true; point to the explicit research that backs your claim.
- You must NOT:
  - Add statements to existing text or otherwise change existing content without clearly indicating the new changes in a diff format for my easy review.

## Safety Rules
- Any changes to existing content, including additions, deletions, or wording changes should include a clear description of the changes in diff format.
- When a change affects technical steps (e.g., partitioning, bootloader, LUKS), call this out explicitly in the diff description so it is easy to spot high‑risk edits.
- When pointing out suspected inaccuracies, include:
  - A short quote or paraphrase of the questionable statement.
  - One or more references (Gentoo Handbook, kernel docs, etc.) that support the correction.

## Workflows
- **When proposing changes**
  - Ensure the suggestion is backed up by documentation or referenced expert knowledge of best practices.
- **When creating a new task document**
  - Start from the “Task Documentation Template” in this file.
  - Fill in all sections, even if some are brief for small tasks.
  - Link to upstream or external docs instead of duplicating long procedures when possible.

- **When updating an existing task document**
  - Use diff format for all edits.
  - Update a “Last updated” metadata field with date and a one‑line reason for the change.
  - If behavior changes due to new kernel/systemd/Gentoo versions, add a short “Version notes” subsection.

## Style
- Include a description of the source that backs up the suggestion; otherwise indicate when suggestions do not have an obvious basis in documentation or discovered expert knowledge.
- At the end of each interaction, include:
  - A one-paragraph state summary.
  - A short TODO list for next time.
- Use clear, task-focused language and prefer short, numbered procedures for anything that involves commands or editing files.

## Task Documentation Template

For each completed task, use the following markdown file structure as a starting point. This is intended for user-facing “how-to” documentation.

1. Metadata
   - Title
   - Status (draft / validated / deprecated)
   - Date created / Last updated
   - Tested on (kernel version, system profile, hardware notes)

2. Overview
   - One or two sentences describing what the task achieves.
   - Brief context: where this task fits in the overall Linux boot project.

3. Motivation and Advantages
   - Why someone would do this.
   - Benefits in terms of boot time, security, simplicity, etc.

4. Prerequisites
   - Assumptions (e.g., “Gentoo with systemd/desktop profile”, “UEFI system”).
   - Required tools or packages.
   - Links to other project tasks that must be completed first.

5. Step-by-Step Instructions
   - Numbered list of steps.
   - Each step includes:
     - The command or configuration change.
     - A short explanation of what and why, especially when the effect is not obvious.

6. Alternatives and Trade-offs
   - List alternative approaches (e.g., different bootloaders, different initramfs tools).
   - Brief pros/cons for each alternative relative to the documented method.

7. Verification
   - How to confirm the change is working (logs, timings, commands).
   - Any quick sanity checks after reboot.

8. Common Pitfalls and Troubleshooting
   - Frequent errors or misconfigurations.
   - How to detect and correct them.

9. References
   - Links to Gentoo Handbook, kernel docs, upstream tools, or blog posts that informed the procedure.
   - Short note on why each reference is relevant. [web:1][web:6][web:10][web:12]
