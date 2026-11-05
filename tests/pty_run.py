#!/usr/bin/env python3
"""Run a command on a pseudo-terminal of a given size, like a real terminal.

Usage: pty_run.py <rows> <cols> <log> <command> [args...]

Copies stdin to the terminal, and everything the command writes to <log>,
unbuffered so tests can poll it. Exits with the command's status once it
exits. Portable replacement for script(1), whose options differ between
macOS and Linux.
"""
import fcntl
import os
import pty
import select
import struct
import sys
import termios


def main():
    rows, cols, log = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    argv = sys.argv[4:]

    pid, fd = pty.fork()
    if pid == 0:
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(0, termios.TIOCSWINSZ, winsize)
        os.execvp(argv[0], argv)

    inputs = [fd, sys.stdin.fileno()]
    with open(log, "ab", buffering=0) as out:
        while True:
            ready, _, _ = select.select(inputs, [], [])
            if fd in ready:
                try:
                    data = os.read(fd, 65536)
                except OSError:  # EIO: the command and its children are gone
                    data = b""
                if not data:
                    break
                out.write(data)
            if sys.stdin.fileno() in ready:
                data = os.read(sys.stdin.fileno(), 65536)
                if data:
                    os.write(fd, data)
                else:
                    inputs.remove(sys.stdin.fileno())

    _, status = os.waitpid(pid, 0)
    sys.exit(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    main()
