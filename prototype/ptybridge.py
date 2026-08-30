#!/usr/bin/env python3
"""stdin/stdout <-> pty 브리지. fd3(제어 채널)로 'resize:<cols>x<rows>\n' 수신.

gcc가 없어 node-pty를 빌드할 수 없는 환경에서 파이썬 표준 라이브러리
pty로 실제 터미널(TTY)을 제공하기 위한 최소 브리지.
사용: python3 ptybridge.py <command> [args...]
"""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios

CTRL_FD = 3


def set_winsize(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


pid, master = pty.fork()
if pid == 0:
    os.environ.setdefault("TERM", "xterm-256color")
    os.execvp(sys.argv[1], sys.argv[1:])

set_winsize(master, 30, 100)

# 제어 채널이 없으면(fd3 미개방) select 목록에서 제외
watch = [0, master]
try:
    os.fstat(CTRL_FD)
    watch.append(CTRL_FD)
except OSError:
    pass

try:
    while True:
        r, _, _ = select.select(watch, [], [])
        if 0 in r:
            data = os.read(0, 65536)
            if not data:
                break
            os.write(master, data)
        if CTRL_FD in r:
            raw = os.read(CTRL_FD, 1024)
            if not raw:
                watch.remove(CTRL_FD)
            else:
                for cmd in raw.decode(errors="ignore").split("\n"):
                    if cmd.startswith("resize:"):
                        try:
                            cols, rows = cmd[7:].split("x")
                            set_winsize(master, int(rows), int(cols))
                            os.kill(pid, signal.SIGWINCH)
                        except (ValueError, OSError):
                            pass
        if master in r:
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            os.write(1, data)
finally:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
