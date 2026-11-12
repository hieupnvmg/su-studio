#!/bin/sh
# Stands in for Blender in tests: answers --version, otherwise renders job["duration"]*fps PNG frames.
case " $* " in *" --version "*) echo "Blender 4.2.3"; echo "	build date: test"; exit 0;; esac
JOB=""; prev=""; for a in "$@"; do [ "$prev" = "--" ] && JOB="$a"; prev="$a"; done
exec /usr/bin/python3 - "$JOB" "$HOME_FOR_TEST" <<'PY'
import json, struct, sys, time, zlib, os, socket
job = json.load(open(sys.argv[1]))
if job.get("script") == "FAIL":
    print("SU_ERROR Script dựng cảnh lỗi: NameError: name 'x' is not defined", flush=True); sys.exit(3)
# The sandbox must stop writes outside the job folder and any network use.
home = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(sys.argv[1])))))
try:
    open(os.path.join(home, "escaped.txt"), "w").write("x")
except OSError:
    pass
try:
    socket.create_connection(("127.0.0.1", 9), timeout=1)
except PermissionError:
    pass
except OSError as error:
    print("SU_ERROR network not sandboxed: %s" % error, flush=True); sys.exit(4)
w, h = job["width"], job["height"]
row = b"\x00" + bytes([200, 120, 40]) * w
raw = zlib.compress(row * h)
def chunk(kind, data): return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
total = int(round(job["duration"] * job["fps"]))
for i in range(1, total + 1):
    open(os.path.join(job["output"], "frame_%04d.png" % i), "wb").write(png)
    print("SU_PROGRESS %d/%d" % (i, total), flush=True)
    if job.get("script") == "SLOW": time.sleep(0.2)
print("SU_DONE", flush=True)
PY
