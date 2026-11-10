"""Minimal read-only TFTP server (RFC 1350, plus blksize option RFC 2348).

Serves files from the ./tftp folder next to this script, to one bind address only.
Write requests are refused. Usage:  python -I tftp_server.py 192.168.1.100
"""
import os, socket, struct, sys, threading

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tftp")
RRQ, WRQ, DATA, ACK, ERROR, OACK = 1, 2, 3, 4, 5, 6


def err(sock, addr, code, msg):
    sock.sendto(struct.pack("!HH", ERROR, code) + msg.encode() + b"\0", addr)


def serve(bind_ip, addr, pkt):
    parts = pkt[2:].split(b"\0")
    name, opts = parts[0].decode(errors="replace"), parts[2:-1]
    options = {opts[i].decode().lower(): opts[i + 1].decode() for i in range(0, len(opts) - 1, 2)}
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((bind_ip, 0)); s.settimeout(2)
    path = os.path.realpath(os.path.join(ROOT, os.path.basename(name)))
    if not path.startswith(os.path.realpath(ROOT)) or not os.path.isfile(path):
        print(f"{addr[0]} asked for {name!r}: not found"); err(s, addr, 1, "File not found"); return
    data = open(path, "rb").read()
    blk = 512
    if "blksize" in options:
        blk = max(8, min(int(options["blksize"]), 1468))
        if not exchange(s, addr, struct.pack("!H", OACK) + f"blksize\0{blk}\0".encode(), 0):
            return
    print(f"{addr[0]} <- {name} ({len(data)} bytes, block {blk})")
    n = 0
    while True:
        n += 1
        chunk = data[(n - 1) * blk: n * blk]
        if not exchange(s, addr, struct.pack("!HH", DATA, n & 0xFFFF) + chunk, n & 0xFFFF):
            print("  transfer aborted"); return
        if len(chunk) < blk:
            break
        if n % 2000 == 0:
            print(f"  {n * blk * 100 // len(data)}%")
    print(f"  done: {len(data)} bytes sent")


def exchange(s, addr, packet, want_block):
    for _ in range(10):
        s.sendto(packet, addr)
        try:
            while True:
                reply, frm = s.recvfrom(1600)
                if frm != addr:
                    continue
                op, b = struct.unpack("!HH", reply[:4])
                if op == ACK and b == want_block:
                    return True
                if op == ERROR:
                    print("  client error:", reply[4:-1]); return False
        except socket.timeout:
            continue
    return False


def main():
    bind_ip = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.100"
    os.makedirs(ROOT, exist_ok=True)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((bind_ip, 69))
    print(f"TFTP (read-only) on {bind_ip}:69 serving {ROOT}: {os.listdir(ROOT)}")
    while True:
        pkt, addr = s.recvfrom(1600)
        op = struct.unpack("!H", pkt[:2])[0]
        if op == RRQ:
            threading.Thread(target=serve, args=(bind_ip, addr, pkt), daemon=True).start()
        elif op == WRQ:
            err(s, addr, 2, "Read-only server")


if __name__ == "__main__":
    main()
