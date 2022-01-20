#!/usr/bin/env python3

import socket

def main():
    addr = '\0bdrm-pi-tty-bridge-socket'

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(addr)
    except socket.err, msg:
        print("connect error:", msg)
        return

    try:
        try:
            data = sock.recv(16)
            print("got", data)
        except socket.err, msg:
            print("read error:", msg)
            return

        try:
            sock.sendall('pong\n')
        except socket.err, msg:
            print("write error:", msg)
            return

    finally:
        sock.close()
