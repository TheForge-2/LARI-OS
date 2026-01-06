# Changelog:

This file will keep track of all publicly released versions of LARI OS, listing all their additions, changes and fixes from the previous one. Only the stable versions found on the `master` branch will appear in the following list, in reverse chronological order.

Commits from `dev` or other development branches will not be tracked in the changelog, so this file will only be updated to the `master` version those commits are based on.

Under each version, there are:

- one-line summary: found at the first line of the commit message;
- summary: the commit message
- functionality changes: they include additions [+], removals [-] and refactoring [@] directly appreciable when using the OS;
- file changes: ordered by category, they keep track whether a file was:
	- modified (binaries excuded):
		- additions (ADD)
		- removals (REM)
		- fixes (FIX)
		- improvements (IMP)
		- comment changes (COM, code files only)
	- created;
	- deleted;
	- renamed (old and new name and location specified).

---

# InDev 0.1:

**2026/01/06:** added CPU and memory detection and improved documentation.

## Summary:

The shell collects information about the CPU, via the CPUID instruction and its leaves, and memory, via BIOS functions: they can then be displayed, with the new 'sysinfo' command, and used to allow or restrict certain features.

CPU information includes vendor, model, feature bits and core topology; the latter is determined by following, when possible, the manufacturer's preferred algorithm (the Intel or AMD one).

Memory detection reports:

- available installed memory (under 4GiB);
- total usable memory (up to the EBDA, the presence of which is checked to improve accuracy);
- free memory (currently reports the same value as usable memory).

New kerel functions have been added: `printd32`, `printr` and `strcmp`, `printd` was renamed to `printd16`.
They, alongside the pre-existing ones, have been separated from `shell.asm` and are attached to it as includes.

New scripts have been added, to simplify the process of testing the OS: `burn-dvd.sh`, `blank-dvd.sh`, `burn-usb.sh`, `restore-usb.sh`, `gen-iso.sh` and `reset-image.sh`.

The instructions to build and execute the OS were completely overhauled: they explain the procedures more clearly and in detail, for both Windows and Linux.
The file is divided in sections, for setting up, testing, compiling and running the OS on real hardware.

A "README.md" file was created to give an introduction to the project and describe its basics.
From now on, changes to the "master" branch will be traced in the "CHANGELOG.md" file.

There have also been general improvements across many files, aimed at optimizing the code and improving the structure and correctness of comments and notes.

## Functionality changes:

[+] Added the new `sysinfo` command, to display CPU and RAM information;

[+] 32-bit integers can now be printed;

[-] If an empty command is sent, the invalid command message isn't printed anymore, it just goes to a new line;

[-] Support for 8086/8088 processors was removed; they now get blocked at the beginning of the shell, for which case and new error message will display;

[@] 	The welcome and help messages were slightly changed, the memory detection error message has been improved and split in 3.

## File changes:

### Modified:

- `src/bootloader/boot.asm`: COM
- `src/shell/shell.asm`: ADD, REM, IMP, COM
- `tools/fat/fat12_reader.c`: IMP
- `Makefile`: COM
- `bochs/bochsrc`: DEL, IMP
- `run.sh`: IMP
- `debug.sh`: IMP
- `LICENSE.txt`: IMP
- `instructions.txt`: ADD, REM, IMP
- `todo.txt`: ADD, REM
- `.gitignore`: DEL

### Created:

- `src/functions/change_page.asm`
- `src/functions/printc.asm`
- `src/functions/printd16.asm`
- `src/functions/printd32.asm`
- `src/functions/printr.asm`
- `src/functions/prints.asm`
- `src/functions/strcmp.asm`
- `build/eltorito_disc.iso`
- `burn-dvd.sh`
- `blank-dvd.sh`
- `burn-usb.sh`
- `restore-usb.sh`
- `gen-iso.sh`
- `reset-image.sh`
- `README.md`
- `CHANGELOG.md`

### Deleted:

None.

### Renamed:

- `bochs/bochs_config` -> `bochs/bochsrc`
- `extra/test.txt` -> `data/test.txt`

---

# InDev 0.0:

**2025/06/05**

First public version of LARI OS.
This initial build features a real mode CLI shell, booted by a single-sector bootloader, alongside 3 working basic commands (`hello`, `help`, `poweroff`).

It marks the starting point for all future development of this operating system, being the first ever version to be tracked on Git and hosted on GitHub.