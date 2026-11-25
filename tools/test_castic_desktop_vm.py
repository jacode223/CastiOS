"""Check the live desktop, glyphs, drive list and restoration of the terminal."""
import tempfile
import time
from pathlib import Path

from PIL import Image
from vm_harness import ROOT, VM

FONT = (ROOT / 'src/console/font8x16.bin').read_bytes()
WHITE = (255, 255, 255)
BACKGROUND = (23, 47, 83)


def glyphs_match(frame, x, y, label, background):
    for i, char in enumerate(label):
        for row in range(16):
            mask = FONT[ord(char) * 16 + row]
            for col in range(8):
                color = WHITE if mask & (0x80 >> col) else background
                if frame.getpixel((x + i * 8 + col, y + row)) != color:
                    return False
    return True


def wait_frame(vm, path, predicate):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        vm.qmp('screendump', {'filename': str(path)})
        with Image.open(path) as frame:
            assert frame.size == (1024, 768)
            if predicate(frame):
                return
        time.sleep(0.05)
    raise AssertionError('Expected desktop frame was never displayed')


def selected(frame, current):
    return all(frame.getpixel((33, y)) == (WHITE if index == current else BACKGROUND)
               for index, y in enumerate((62, 142, 222)))


for slots in ((), (0, 3)):
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        drives = {}
        for slot in slots:
            path = work / f'disk{slot}.img'
            with path.open('wb') as file:
                file.truncate(32 * 1024 * 1024)
            drives[slot] = path
        vm = VM(work, disk_positions=drives, memory=256 if slots else 32)
        try:
            vm.cmd('castctl console', '1024x768 RGB32')
            vm.cmd('cat /lib/desk.cas', 'fn f')
            vm.cmd('castic /desk.cas /desk.app', 'compilado i386')
            start = len(vm.out())
            vm.type('exec /desk.app'); vm.key('ret')
            def expect(predicate):
                wait_frame(vm, work / 'screen.ppm', predicate)
            nav = (36, 51, 109)
            expect(lambda f: selected(f, 0) and glyphs_match(f, 336, 84, 'i386', nav))
            vm.key('2')
            def inventory(f):
                if not selected(f, 1) or not glyphs_match(f, 336, 84, 'HDD:', nav):
                    return False
                for slot in range(4):
                    label = 'hd' + chr(97 + slot) if slot in slots else '   '
                    if not slots and slot == 0:
                        label = '0  '
                    if not glyphs_match(f, 376 + slot * 32, 84, label, nav):
                        return False
                return True
            expect(inventory)
            vm.key('3')
            expect(lambda f: selected(f, 2) and glyphs_match(f, 336, 84, '1-3', nav))
            vm.key('x')
            expect(lambda f: selected(f, 2))
            vm.key('1')
            expect(lambda f: selected(f, 0) and glyphs_match(f, 336, 84, 'i386', nav))
            vm.key('esc' if slots else 'q')
            vm.wait('Programa termino. EAX=113', start)
            vm.wait('asm:/ > ', start)
            expect(lambda f: f.getpixel((0, 0)) == (16, 16, 16) and
                   f.getpixel((33, 62)) != WHITE)
            vm.cmd('echo terminal', 'terminal')
        finally:
            vm.close()
print('OK: live Castic, exact bitmap glyphs, all selections, empty and dual-drive inventory, q/Esc.')
