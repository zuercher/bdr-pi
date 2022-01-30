#!/usr/bin/env python3

import socket
import json
import time

FRIENDLY_NAME = 'RaceCapture/Pro MK3'
START_TIME = time.monotonic_ns()

def read(sock):
    try:
        res = sock.recv(4096)
        return res.decode('utf-8')
    except socket.error as e:
        print("DEVICE RECV ERROR:", e)
        return None


def write(sock, s):
    try:
        sock.sendall(s.encode('utf-8'))
        return True
    except socket.error as e:
        print("DEVICE SEND ERROR:", e)
        return False

def version_info():
    return {
        'major': 2,
        'minor': 18,
        'bugfix': 4,
        'serial': '1234567890',
        'git_info': '2.18.4',
    }

def uptime():
    now = time.monotonic_ns()
    return int((now - START_TIME) / 1000000000)

def handle(msg):
    payload = json.loads(msg)
    resp = {}

    if 'getVer' in payload:
        resp = {
            'ver': {
                'name': 'RCP_MK3',
                'fname': FRIENDLY_NAME,
                'release_type': 'RELEASE_TYPE_OFFICIAL',
            } | version_info(),
        }
    elif 'getCapabilities' in payload:
        resp = {
            'capabilities': {
                'flags': [
                    'activetrack',
                    'adc',
                    # 'bt',
                    'can',
                    'can_term',
                    # 'cell',
                    'gpio',
                    'gps',
                    'imu',
                    # 'lua',
                    'odb2',
                    'pwm',
                    'telemstream',
                    'tracks',
                    'timer',
                    'usb',
                    'sd',
                    # 'wifi',
                    # 'camctl',
                ],
                'channels': {
                    'analog': 1,
                    'imu': 1,
                    'gpio': 1,
                    'timer': 1,
                    'pwm': 1,
                    'can': 1,
                    'obd2': 1,
                    'canChan': 1,
                },
                'sampleRates': {
                    'gps': 1,
                    'sensor': 1,
                },
                'db': {
                    'script': 1,
                    'tracks': 1,
                    'sectors': 1,
                },
            },
        }
    elif 'getStatus' in payload:
        resp = {
            'status': {
                'system': {
                    'model': FRIENDLY_NAME,
                    'uptime': uptime(),
                } | version_info(),
                'GPS': {
                    'init': 1, # GPS_STATUS_PROVISIONED
                    'qual': 2, # GPS_QUALITY_3D
                    'lat': 37.7749,
                    'lon': -122.4194,
                    'sats': 6,
                    'DOP': 0.5, # "ideal"
                },
                # 'cell': {},
                'bt': {
                    'init': 0, # BT_STATUS_NOT_INIT
                },
                'logging': {
                    'status': 3, # LOGGING_STATUS_CARD_NOT_PRESENT
                    'dur': 0,
                },
                'track': {
                    'status': 0,
                    'valid': False,
                    'trackId': 0,
                    'inLap': 0,
                    'armed': 0,
                },
            },
        }
    return json.dumps(resp)


def main():
    addr = b'\0bdr-pi-tty-bridge-socket'

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(addr)
    except socket.error as e:
        print("connect error:", e)
        return

    try:
        buffer = None
        while True:
            s = read(sock)
            if s is None:
                return

            lines = s.split('\n')
            lines.reverse()
            while len(lines) > 1:
                line = lines.pop()
                if buffer:
                    line = buffer + line
                    buffer = None

                print("DEVICE RECV: ", line.strip())
                resp = handle(line)
                print("DEVICE SEND: ", resp)
                if not write(sock, resp+"\r\n"):
                    break

            if len(lines) == 1 and lines[0] != '':
                # partial line received
                buffer = lines[0]

    finally:
        print("DEVICE CLOSE")
        sock.close()


if __name__=="__main__":
    main()
