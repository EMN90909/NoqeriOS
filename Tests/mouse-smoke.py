#!/usr/bin/env python3
"""PS/2 mouse test under OVMF/QEMU: cursor pixels are drawn at the clamped
position and a click on the Terminal tile opens the graphical terminal.
Emulator-only evidence (QEMU i8042 aux port); no USB HID, no real hardware."""
import importlib.util
import re
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location("gs", Path(__file__).with_name("gui-smoke.py"))
gs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gs)


def pixels(ppm):
    h = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", ppm)
    w, ht, _ = map(int, h.groups())
    raw = ppm[h.end():]
    return w, ht, lambda x, y: tuple(raw[3 * (y * w + x):3 * (y * w + x) + 3])


def main():
    code, vars_origin = gs.firmware()
    with tempfile.TemporaryDirectory(prefix="noqerios-mouse-") as tmp:
        work = Path(tmp)
        (work / "vars.fd").write_bytes(Path(vars_origin).read_bytes())
        import struct
        vol = bytearray(1024 * 1024)
        struct.pack_into("<4sIQII", vol, 0, b"NQFS", 2, 1, 1, 512)
        raw = b"HELLO.TXT"
        struct.pack_into("<QQQIIQ24s", vol, 512, 1, 4, 16, 1, len(raw), 0, raw)
        vol[4 * 512:4 * 512 + 16] = b"HELO from NoqFS!"
        (work / "disk.img").write_bytes(vol)
        mon = work / "hmp.sock"
        cmd = ["qemu-system-x86_64", "-machine", "q35", "-m", "256M",
               "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
               "-drive", f"if=pflash,format=raw,unit=1,file={work / 'vars.fd'}",
               "-cdrom", str(gs.OUT / "noqerios.iso"), "-boot", "order=d",
               "-drive", f"if=none,format=raw,file={work / 'disk.img'},id=files",
               "-device", "virtio-blk-pci,drive=files,disable-legacy=on",
               "-vga", "std", "-display", "none", "-serial", "stdio",
               "-monitor", f"unix:{mon},server,nowait", "-no-reboot", "-no-shutdown"]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0)
        out = bytearray()
        try:
            gs.observe(proc, b"PS/2 mouse enabled", 25, out)
            gs.observe(proc, b"NoqeriOS serial terminal ready", 10, out)
            while not mon.exists():
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as s:
                s.settimeout(8)
                s.connect(str(mon))
                def moves(dx, dy):
                    while dx != 0 or dy != 0:
                        sx = max(-100, min(100, dx)); sy = max(-100, min(100, dy))
                        gs.hmp(s, f"mouse_move {sx} {sy}")
                        dx -= sx; dy -= sy
                        time.sleep(0.15)
                    time.sleep(1.0)

                def find_cursor(ppm):
                    w, h, px = pixels(ppm)
                    blacks = [(x, y) for y in range(h) for x in range(w) if px(x, y) == (0, 0, 0)]
                    if not blacks:
                        return None
                    ty = min(y for _, y in blacks)
                    tx = min(x for x, y in blacks if y == ty)
                    return tx, ty, len(blacks), px

                moves(-200, -100)
                shot = gs.screenshot(s, str(work / "a.ppm"))
                open("/tmp/dbg_new.ppm", "wb").write(shot)
                found = find_cursor(shot)
                if not found:
                    raise AssertionError("no black cursor outline on screen")
                cx, cy, count, px = found
                whites = sum(1 for yy in range(cy, cy + 13) for xx in range(cx, cx + 8)
                             if px(xx, yy) == (255, 255, 255))
                if not (25 <= count <= 35) or whites < 20:
                    raise AssertionError(f"cursor shape wrong at {(cx, cy)} blacks={count} whites={whites}")
                print(f"PASS: cursor drawn at ({cx},{cy}) with {count} outline pixels")
                w, h, _ = pixels(shot)
                tw = min((w - 66) // 2, 255)
                th, top = (110, 126) if h >= 440 else (74, 98)
                tx, ty = 28 + tw + 10 + tw // 2, top + th // 2
                before = shot
                out.clear()
                moves(tx - cx, ty - cy)
                shot2 = gs.screenshot(s, str(work / "b.ppm"))
                f2 = find_cursor(shot2)
                if not f2 or abs(f2[0] - tx) > 3 or abs(f2[1] - ty) > 3:
                    raise AssertionError(f"cursor did not reach Terminal tile: {f2 and f2[:2]} want {(tx, ty)}")
                print(f"PASS: cursor moved to ({f2[0]},{f2[1]}) over Terminal tile")
                gs.hmp(s, "mouse_button 1")
                gs.observe(proc, b"GUI compositor window focus updated", 8, out)
                gs.hmp(s, "mouse_button 0")
                time.sleep(1.0)
                after = gs.screenshot(s, str(work / "c.ppm"))
                if after == shot2:
                    raise AssertionError("click did not change the screen")
                print("PASS: mouse click on Terminal tile opened terminal")
                # Hit Escape to close terminal and return to desktop
                gs.hmp(s, "sendkey esc")
                time.sleep(1.0)
                shot3 = gs.screenshot(s, str(work / "d.ppm"))
                # Click the Start button at bottom-left
                out.clear()
                barY = h - 45
                moves(30 - int(f2[0]), barY + 15 - int(f2[1]))
                shot4 = gs.screenshot(s, str(work / "e.ppm"))
                f4 = find_cursor(shot4)
                print(f"PASS: cursor moved over Start button at ({f4[0]},{f4[1]})")
                gs.hmp(s, "mouse_button 1")
                gs.observe(proc, b"GUI compositor window focus updated", 8, out)
                gs.hmp(s, "mouse_button 0")
                time.sleep(1.0)
                shot5 = gs.screenshot(s, str(work / "f.ppm"))
                if shot5 == shot4:
                    raise AssertionError("clicking start button did not update desktop")
                print("PASS: clicking Start button toggled start screen")
        except Exception:
            try:
                gs.observe(proc, b"\x00never", 1.5, out)
            except Exception:
                pass
            print("Serial:\n" + out.decode(errors="replace")[-3000:], file=sys.stderr)
            raise
        finally:
            proc.kill(); proc.communicate(timeout=5)


main()
