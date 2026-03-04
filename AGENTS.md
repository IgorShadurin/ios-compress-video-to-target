# AGENTS.md

## Command Knowledge Registry

- Registered file: `BUILD_LAUNCH_COMMANDS.md`
- Purpose: this file is the canonical command reference for this repo.
- Data inside:
  - dedicated simulator boot/build/install/launch commands
  - one-shot build/install/launch command
  - build-log capture command
  - fresh iPhone 17 simulator creation command
  - exact light/dark showcase screenshot capture commands for all 14 screens
  - screenshot output validation commands

## Usage Rule

When a task involves local build, simulator run, or showcase screenshot generation, use commands from `BUILD_LAUNCH_COMMANDS.md` first before inventing new command sequences.

## Test Media Storage Policy

- Large/manual test media files must be stored only in:
  - `/Users/test/XCodeProjects/CompressTarget_data`
- Do not place such files inside the main project repo tree (`/Users/test/XCodeProjects/CompressTarget`).
- When adding or updating tests that depend on large/manual media, reference files from `CompressTarget_data` paths.
