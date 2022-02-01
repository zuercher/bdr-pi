#!/usr/bin/env python3

import argparse
import json
import signal
import socket
import time

from capabilities import Capabilities
from lapconfig import LapConfig
from logging import Logging
from status import Status
from telemetry import Telemetry
from version import Version

class Simulator(Logging):
    def __init__(self, addr):
        Logging.__init__(self)

        self.addr = addr
        self.sock = None
        self.closing = False

        self.handlers = [
            Capabilities.instance(),
            LapConfig.instance(),
            Status.instance(),
            Telemetry.instance(),
            Version.instance(),
        ]

        self.executors = { cmd: handler.execute for handler in self.handlers for cmd in handler.commands() }


    def set_verbosity(self, level):
        super().set_verbosity(level)
        for h in self.handlers:
            h.set_verbosity(level)


    def _connect(self):
        if self.closing:
            self.error("connect error: closing")
            return None

        self.print(2, "DEVICE CONNECT")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            self.sock.connect(self.addr)
        except socket.error as e:
            self.error("connect error:", e)
            return None

        return self.sock


    def connected(self):
        return self.sock is not None


    def connection(self):
        if self.connected():
            return self.sock

        return self._connect()


    def close(self):
        self.print(2, "DEVICE CLOSE")
        self.closing = True
        if self.sock:
            self.sock.close()
        self.sock = None


    def read(self):
        conn = self.connection()
        if not conn:
            return None

        try:
            res = self.sock.recv(4096)
            return res.decode('utf-8')
        except socket.error as e:
            if not self.closing:
                self.error("DEVICE RECV ERROR:", e)
            return None


    def write(self, s):
        conn = self.connection()
        if not conn:
            return None

        try:
            self.sock.sendall(s.encode('utf-8'))
            return True
        except socket.error as e:
            self.error("DEVICE SEND ERROR:", e)
            return None


    def handle(self, data):
        payload = json.loads(data)
        resp = {}
        for cmd, query in payload.items():
            f = self.executors.get(cmd)
            if f:
                resp = resp | f(cmd, query)
            else:
                self.print(1, "DEVICE SENT UNKNOWN COMMAND", cmd)
                self.print(1, "       QUERY", query)

        if len(resp) == 0:
            self.print(2, "NO RESPONSE")
            return None

        return json.dumps(resp, indent=None, separators=(',', ':'))


    def run(self):
        signal.signal(signal.SIGINT, lambda sig, frm: self.close())

        try:
            buffer = None
            while True:
                s = self.read()
                if s is None:
                    return

                lines = s.split('\n')
                lines.reverse()
                while len(lines) > 1:
                    line = lines.pop()
                    if buffer:
                        line = buffer + line
                        buffer = None

                    self.print(2, "DEVICE RECV: ", line.strip())
                    resp = self.handle(line)
                    if resp:
                        self.print(2, "DEVICE SEND: ", resp)
                        if not self.write(resp+"\r\n"):
                            break

                if len(lines) == 1 and lines[0] != '':
                    # partial line received
                    buffer = lines[0]

        finally:
            self.close()
            print()


if __name__== "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--socket', '-s', metavar='SOCKET', dest='addr',
                        default='@bdr-pi-tty-bridge-socket',
                        help='Unix domain socket to use. Prefix with @ to use an abstract socket.')
    parser.add_argument('--verbose', '-v', action='count', dest='verbosity', default=0,
                        help='Increase verbosity level.')
    args = parser.parse_args()

    addr = bytearray(args.addr, encoding='ascii')
    if args.addr[0] == '@':
        addr[0] = 0

    sim = Simulator(addr)
    sim.set_verbosity(args.verbosity)
    sim.run()
