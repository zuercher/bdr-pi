#!/usr/bin/env python3

import serial.serialposix

def main():
    dev_name = '/dev/ttyUSB_FAKE_RACECAP0'

    ser = serial.serialposix.Serial(dev_name, timeout=3, write_timeout=3)

    try:
        print("writing")
        ser.write(b'ping')
    except serial.SerialException as e:
        print("write error:")
        print(e)
        ser.close()
        return

    try:
        print("reading")
        result = ser.read(5)
        print("got response:", result)
    except serial.SerialException as e:
        print("read error:")
        print(e)

    ser.close()


if __name__=="__main__":
    main()
