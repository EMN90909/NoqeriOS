# Noqeri Shell 1.0

NoqeriOS now includes a small **line-oriented command shell**, inspired by
the familiar structure of Windows CMD but designed to be easier to learn.
It is implemented in native Noqeri, not an embedded Linux shell.

## Open the terminal

On a graphics-capable x86-64 boot, press `S` to select the **Terminal**
tile on the monochrome Start screen, then press `Z`. The resulting
graphical terminal is charcoal with white text. Enter commands using a
PS/2-compatible keyboard. Press `Esc` to return to the Start screen.

On headless machines, boot QEMU with `-serial stdio` and type at the
`N:\\>` prompt. This is the full command shell, not merely a debug log.

Commands are case-insensitive, execute on Enter and accept Backspace.
Commands are limited to 127 input bytes.

| Command | Alias | Meaning |
|---|---|---|
| `help` | `h` | List commands |
| `dir` | `ls` | List entries in the current NoqFS directory |
| `cd DOCUMENTS` | | Enter a folder |
| `cd ..` | | Go to the parent directory |
| `pwd` | | Show the current directory key |
| `type README.TXT` | `cat README.TXT` | Preview up to 512 bytes of a file |
| `cls` | `clear` | Clear the terminal |
| `echo hello` | | Echo text |
| `ver` | `info` | Show OS version |
| `mem` | `memory` | Memory-core status |
| `tasks` | `ps` | Scheduler status |
| `net` | `network` | Network status |
| `ping` | | Test configured IPv4 gateway |
| `dns` | | Resolve example.com |
| `tcp` | | Probe the local HTTP fixture |
| `files` | `start` | Open graphical File Explorer |
| `gui` | | Cycle the Start selection |
| `reboot` | | Report reset instruction; does not reboot |

NoqFS v1 exposes numeric keys such as `KEY-0000000000000001` instead
of actual filenames. NoqFS v2 supports filenames and folders. File
browsing is read-only; `del`, `copy`, `move`, `mkdir`, pipes and
external program execution are not implemented. The shell does not
pretend otherwise.

The graphical terminal currently uses a bounded 40-column by 16-row
bitmap text buffer, with basic PS/2 US keyboard scan codes. USB keyboard
drivers, keyboard layouts, fonts and terminal escape sequences are not
complete. COM1 works independently of the graphical display.

## Testing

```sh
bash build.sh --uefi-bootstrap
python3 Tests/gui-smoke.py
python3 Tests/terminal-interaction.py
```

CI launches the real kernel in QEMU. The interactive test sends commands
to the live serial shell and validates the responses. The GUI test
opens the Terminal tile, types `help` using PS/2 key injection, and
checks both the shell output and the displayed framebuffer.
