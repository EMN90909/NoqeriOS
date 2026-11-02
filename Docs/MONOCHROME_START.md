# NoqeriOS monochrome Start desktop

The native NoqeriOS GUI uses a Windows 8-inspired **tile navigation layout**
without Microsoft branding, Windows symbols, or Microsoft's bright tile colors.

## Design

- Background: charcoal #303030; top and bottom rails: #242424.
- Four rectangular tiles arranged in two columns, using neutral greys
  #555555, #666666, and #777777.
- Labels and tile icon silhouettes are white/near-white.
- Active selection uses a white outline, not a colored accent.
- FILES opens the existing read-only NoqFS File Explorer.
- TERMINAL and SYSTEM are present as launcher tiles; they do not yet create
  independent graphical applications. HOME switches the Start/desktop view.
- File Explorer's existing light interface uses neutral grayscale accents.
- The GUI is software-rasterized, with optional VirtIO-GPU 2D presentation.

## Keyboard

- `A` selects the Files tile.
- `S` advances to the next tile.
- `Z` activates the focused tile.
- `F` opens or closes the File Explorer directly.
- Within Explorer, `J`/`K` select entries and `E`/`B` navigate folders.
- The existing serial-terminal keyboard mapping is retained.

This is a framebuffer prototype, not the Microsoft Windows shell. It
doesn't implement mouse input, launchable user processes, the Charms bar,
or the Windows AppX model. Labels still use a 5x7 bitmap font.

## Verification

The existing `Tests/gui-smoke.py` boots the original UEFI loader under
OVMF, captures actual framebuffer screenshots and verifies focus redraw
and Explorer keyboard navigation. It runs in the GitHub Actions UEFI job.
A valid NoqeriOS build also runs 128 MB, 256 MB and 768 MB BIOS smoke
tests, including the optional VirtIO GPU presenter.
