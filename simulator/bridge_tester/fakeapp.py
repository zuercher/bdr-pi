#!/usr/bin/env python3

import serial.serialposix

def write(ser, s):
    try:
        ser.write(s.encode('utf-8'))
        return True
    except serial.SerialException as e:
        print("APP SEND ERROR:", e)
        return False

def read1(ser):
    try:
        return ser.read(1).decode('utf-8')
    except serial.SerialException as e:
        if str(e).startswith('device reports readiness'):
            return ''
        else:
            print("APP RECV ERROR:", e)
            raise

def read(ser):
    msg = ''
    while True:
        c = read1(ser)
        if c == '':
            return None
        msg += c
        if msg[-2:] == '\r\n':
            msg = msg[:-2]
            return msg
        if msg[-1:] == '\n':
            msg = msg[:-1]
            return msg


def main():
    dev_name = '/dev/ttyUSB_FAKE_RACECAP0'

    ser = serial.serialposix.Serial(dev_name, timeout=3, write_timeout=3)

    msgs = ['{"getVer":null}\n']

    try:
        for m in msgs:
            print("APP SEND:", m.strip())
            if not write(ser, m):
                break

            s = read(ser)
            if s == None:
                break
            print("APP RECV:", s)
    finally:
        ser.close()


if __name__=="__main__":
    main()
