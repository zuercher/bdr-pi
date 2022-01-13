#!/usr/bin/env python3

import fileinput
import logging

logging.basicConfig(filename='/home/pi/dumb.log',
                    encoding='utf-8', level=logging.INFO)


for line in fileinput.input():
    line.rstrip()
    if line == '{"getVer":null}':
        print('{"ver":{"name":"DEVICE_NAME","fname":"FRIENDLY_NAME","major":2,"minor":18,"bf_name":4,"serial":"ABCDEF","git_info":"v2.18.4","release_type":"official"}}')
        logging.info("sent version")
    else:
        logging.info(f"got {line}")
