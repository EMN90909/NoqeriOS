# Noqeri Shell: command prompt for NoqeriOS

NoqeriOS's native Noqeri-language terminal is available over COM1 and inside
the monochrome Start screen. Its syntax resembles Windows CMD but emphasizes
short commands, simple aliases and descriptive errors. It executes a line
only when you press Enter, not on every keypress.

## Quick reference

| Purpose | Windows-like command | Simpler alternative |
|---|---|---|
| List files | `dir` | `ls` or `list` |
| Change folder | `cd DOCUMENTS` | `go DOCUMENTS` |
| Parent directory | `cd ..` | `up` or `back` |
| Current directory | `pwd` | `where` |
| Read a file (512-byte preview) | `type README.TXT` | `read README.TXT` or `cat README.TXT` |
| Print a message | `echo hello` | `say hello` |
| Clear the screen | `cls` | `clear` |
| OS identity | `ver` | `info` |
| Replay previous command | `again` | `again` |
| General help | `help` | `h` |

Additional commands: `mem`/`memory`, `tasks`/`ps`, `net`/`network`,
`ping` (configured gateway only), `dns` (example.com only),
`tcp` (local networking fixture), `files`/`start` (Explorer),
`gui` (change Start selection), `reboot` (informational only).

Command names ignore case. Arguments retain their characters as typed.
The command line is capped at 127 printable characters; Backspace edits.
`again` executes the last nonempty command, not another `again`.

## Examples

```text
N:\> help
N:\> dir
N:\> go DOCUMENTS
N:\> list
N:\> read README.TXT
N:\> back
N:\> say hello noqerios
N:\> again
```

## Important restrictions

NoqFS v2 supports named files and nested folder keys; v1 supplies
synthetic `KEY-<16 hex digits>` names. File navigation is read-only:
`copy`, `move`, `del`, `mkdir` and piping are not implemented and
must not be treated as working. The terminal cannot launch arbitrary
Windows executables or external native applications yet. `ping`, `dns`
and `tcp` are bounded diagnostics, not a general network toolkit.

The graphical Terminal uses the kernel's software compositor and optional
VirtIO GPU presentation. COM1 input is independently supported in QEMU.
Graphical keyboard input currently relies on PS/2 scancodes; USB HID
keyboards and a full Unicode text engine remain future work.

## Tests

```bash
bash Tests/qemu-smoke.sh
python3 Tests/terminal-interaction.py --memory 256M
```

The Python integration test boots the actual BIOS ISO in QEMU, enters
shell commands over COM1, checks real replies and verifies filesystem
reading, error handling, aliases, and repeat-last behavior.
The UEFI CI job separately checks that the graphical shell is displayed.
