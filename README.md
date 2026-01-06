# **LARI OS**

## About the project

Welcome to LARI OS!

The current version is InDev 0.1.

LARI OS is a 16-bit real mode operating system (OS), developed entirely by me (Alessandro Meles) for educational purposes.
The official repository is hosted on GitHub at "https://github.com/TheForge-2/LARI-OS".

The repository is organized in branches as follows:

- `master` branch: it contains all the official stable releases, named with a major.minor.revision versioning;
- `dev` branch: here go all the intermediary updates, which are generally stable but not designed for actual use (there might be bugs, missing features and outdated documentation);
- other minor branches: they are mostly for work in progress features and should not be considered neither finished nor stable (therefore they are not included in the repository).

The goal of this project is to create a stable and functional operating system, by avoiding design inconsistencies and trying to make it as bug-proof as possible.
I'm currently prioritising a solid fundation over new features, with the aim of writing always the most efficient code that at the same time takes into account all the possible edge cases.

For instructions on how to test the OS (and much more), see `instructions.txt`.
Before doing that though, please read the license in `LICENSE.txt`, it's short, I promise!

The OS currently has little functionality, but the plan is to keep on expanding it: to see what is programmed to come, check `todo.txt`. To instead see what was added, changed or fixed in the current version or in past ones, see `CHANGELOG.md`.

## Description

The program is based on a command line interface (CLI), so everything is done via commands.
It consists of a single-sector FAT12 bootloader and a monolithic shell, that acts both as a CLI terminal and a kernel.

Being a real mode program, this operating system has the following features and restrictions:

- It bases its core functionalities on BIOS interrupts;
- Due to 20-bit memory addressing, it fully operates in the lower memory (<1024KiB);
- If the CPU supports them, it can access 32-bit registers and arithmetics from real mode.

After being executed, the bootloader looks for the shell in the FAT12 filesystem image, parsing the root directory for `shell.bin`.
Following the FAT chain, all the sectors are loaded in memory and control is transferred to the shell.

The shell then tries to detect some information about the computer, used to determine what features are available and how much free memory there is.
If this fails, it will throw a warning: you can decide to continue with limited functionalities or otherwise exit.
These limitations prevent loading any more files and data in memory.

Then the code enters the main loop, which prompts for a command:
after `Enter` is pressed, it starts parsing the command table and, if it finds a match, it executes the command.
After the execution completed, the shell will prompt for another command.

The video mode is set to text 80*25 4-bit colour (for both background and foreground), but the output is limited to monochrome.
There are 8 pages, natively provided by the BIOS, which store the output of previous commands:
when 1 page gets filled, it will automatically switch to the next one, clearing the oldest output page.

## How to use

### Get it running

First, you need to get the OS running.
If you don't know how, in `instructions.txt` you'll find very detailed instructions to use LARI OS in various environments:
as long as an emulator or virtual manager is supported, you can run it on any other OS, like Linux or Windows.

Following the provided instructions, you will be able to download the OS, set up the required programs and test it in a confined environment.

Don't be scared by the length of the file, for basic usage you'll only need the first few sections;
the rest is dedicated to more experienced users who want to experiment with the OS, by modifying the source or running it on real hardware.

### Test the OS

After beginning the execution, you will see a welcoming message, which contains very basic information;
below that you'll find a prompt: type the desired command and send it by pressing `Enter`.

Since it is a command-line-only operating system, there is no graphical interface and everything must be done with commands.

There are currently 4 available commands (as reported by the `help` command):

- `hello`: display the welcome message, which contains basic information;
- `help`: print more information and instructions and list the available commands;
- `sysinfo`: display information about the system (not yet fully complete);
- `poweroff`: put the system in a safe state for a physical shutdown (currently has limited functionalities).

Every other command not listed by `help` is not valid.

Arrow keys are not yet supported, but you can still use `Backspace` to delete the previous character.

There are 8 pages which store all the terminal output; once one gets filled, the OS switches to the next.
After all 8 pages have been filled, the oldest one will be overwritten to make space for newer text.
Use `PgUp` and `PgDn` to see respectively older and newer output; use `Home` instead to directly return to the newest page.

## Table of contents:

The following list contains all the project files and folders included in the repository (folders first, aphabetical order):

- `bochs`: Bochs configuration files and logs folder

    - `bochsrc`: Bochs configuration file

- `build`: all the program's built binaries

    - `tools`: executables for C testing tools

        - `fat12_reader`: FAT12 image reader C tool executable

    - `bootloader.bin`: bootloader's assembled binary

    - `copy_floppy.img`: copy of the OS image (for use in emulators and VMs)

    - `eltorito_disc.iso`: ElTorito bootable ISO 9660 image

    - `main_floppy.img`: the entire raw floppy OS image

    - `shell.bin`: shell's assembled binary

- `data`: extra data files included in the image (text and images for example)

    - `test.txt`: text file used for testing purposes

- `src`: all the OS source code

    - `bootloader`: all the bootloader source code

        - `boot.asm`: the bootloader main code

    - `shell`: all the shell source code

        - `shell.asm`: the shell main code

    - `functions`: shell functions source code

        - `change_page.asm`: change the displayed page

        - `printc.asm`: print a character

        - `printd16.asm`: print a 16-bit integer

        - `printd32.asm`: print a 32-bit integer

        - `printr.asm`: print a character repeatedly

        - `prints.asm`: print a string

        - `strcmp.asm`: compare two strings

- `tools`: contains all the C tools source code

    - `fat`: contains all the FAT C tools source code

        - `fat12_reader.c`: FAT12 image reader C code

- `blank-dvd.sh`: script for blanking RW DVDs

- `burn-dvd.sh`: script for burning the ISO to a disc

- `burn-usb.sh`: script for flashing the image to a USB drive

- `CHANGELOG.md`: Markdown record of past changes

- `debug.sh`: script for running the OS in Bochs

- `gen-iso.sh`: script to generate an ElTorito ISO

- `instructions.txt`: instructions for testing and building the OS

- `LICENSE.txt`: license file

- `Makefile`: used by Make to build the entire project

- `README.md`: Markdown introduction file

- `reset-image.sh`: script to reset the copy image

- `restore-usb.sh`: script to format a USB drive to FAT32

- `run.sh`: script for running the OS in QEMU

- `todo.txt`: list of likely future updates

This list is also available at the end of the `instructions.txt` file.

## Credits

Special thanks go to professor Riccardo Dossena and professor Clementino Visigalli for helping and supporting this project.

Thank you for trying out LARI OS!

I hope you liked this project, have fun!

\- Alessandro Meles // TheForge-2
