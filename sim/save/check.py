"""Run tb on a .sav and check it: what the RAM holds after loading, and the
file that goes back. python3 -I check.py <sim binary> <scratch dir> <.sav>"""
import os, subprocess, sys

sim, scratch, sav = sys.argv[1:4]
data = open(sav, 'rb').read()
name = os.path.basename(sav)
os.makedirs(scratch, exist_ok=True)
hin, hram, hout = (os.path.join(scratch, x) for x in ('in.hex', 'ram.hex', 'out.hex'))
open(hin, 'w').write(''.join('%02x\n' % b for b in data))
subprocess.run([sim, '+in=' + hin, '+size=%d' % len(data), '+out=' + hout, '+ram=' + hram],
               check=True, stdout=subprocess.DEVNULL)
ram = bytes(int(x, 16) for x in open(hram).read().split())
out = bytes(int(x, 16) for x in open(hout).read().split())

packed = len(data) <= 65536
want = data.ljust(65536, b'\xff') if packed else bytes(data[2 * k + 1] for k in range(65536))
fails = []
if ram != want:
    k = next(i for i in range(65536) if ram[i] != want[i])
    fails.append('RAM byte %d is %02x, should be %02x' % (k, ram[k], want[k]))
if len(out) != 131072:
    fails.append('wrote %d bytes back, not 131072' % len(out))
elif out[1::2] != ram or out[0::2] != ram:
    fails.append('the file back is not the RAM on both bytes of each word')
if not packed and out[1::2] != data[1::2]:
    fails.append("the file back's odd bytes differ from the file's")
if len(out) == 131072:
    # the file back, loaded again, is the same RAM (playing on after a quit)
    back = os.path.join(scratch, 'back.sav')
    open(back, 'wb').write(out)
    subprocess.run([sim, '+in=' + hin.replace('in.hex', 'back.hex'), '+size=131072', '+out=' + hout, '+ram=' + hram],
                   check=True, stdout=subprocess.DEVNULL) if open(hin.replace('in.hex', 'back.hex'), 'w').write(''.join('%02x\n' % b for b in out)) else None
    if bytes(int(x, 16) for x in open(hram).read().split()) != ram:
        fails.append('the file back, loaded again, is not the same RAM')
print(('FAIL ' if fails else 'ok   ') + ('64 KB' if packed else '128 KB') + '  ' + name)
for f in fails:
    print('     ' + f)
sys.exit(1 if fails else 0)
