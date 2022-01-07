#!/usr/bin/env python3

import logging
import json
import os
import select

class RaceCaptureSim:
    def __init__(self, config_path):
        self.config_path = config_path
        self.config = None

    def load(self):
        logging.debug(f"load from {self.config_path}")

        try:
            config = open(self.config_path, 'r', encoding='utf-8')
            with config:
                self.config = json.load(config)
        except OSError as e:
            # use defaults
            logging.debug(f"unable to read {self.config_path}: {os.strerror(e.errno)}")
            self.config = {}
        except json.JSONDecodeError as e:
            logging.error(f"unable to parse {self.config_path}: {e.lineno}:{e.colno}: {e.msg}")
            return False

        # TODO: validate config
        return True

    def run(self):
        device_path = self.config.get('device_path', '/dev/ttyUSB_RACECAPTURE_SIM')
        logging.info(f"starting sim on {device_path}")

        try:
            pipe_fd = os.open(device_path, flags=os.O_RDWR|os.O_APPEND|os.O_NONBLOCK)
            while True:
                r, _, _ = select.select([pipe_fd], [], [])
                if len(r) == 0:
                    continue
                elif r[0] != pipe_fd:
                    logging.error(f"invalid fd selected for read: {r[0]} (expected {pipe_fd})")
                    continue

                bs = os.read(pipe_fd, 512)
                logging.info(f"recv: {bs.decode('utf-8')}")


        except OSError as e:
            logger.error(f"error on read path: {os.strerror(e.errno)}")
        finally:
            if pipe_fd != 0:
                os.close(pipe_fd)

if __name__ == '__main__':
    import argparse
    import sys

    home_dir = os.getenv('HOME', '.')
    default_config_path = f"{home_dir}/.config/racecapture_sim/config.json"

    parser = argparse.ArgumentParser(
        'Simulates a RaceCapture Pro/Mk3',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--config', metavar='PATH', type=str, help='config file path',
                        default=default_config_path)
    parser.add_argument('--log-file', metavar='PATH', type=str, help='log file path',
                        default='-', dest='log_file')
    parser.add_argument('--log-level', type=str, default='INFO',
                        choices=['DEBUG','INFO', 'WARNING', 'ERROR', 'CRITICAL'], help='log level',
                        dest='log_level')
    args = parser.parse_args()

    log_file = args.log_file
    if log_file == '-':
        log_file = None
    log_level = getattr(logging, args.log_level.upper(), logging.INFO)
    log_format = '%(asctime)s [%(levelname)s] %(message)s'
    logging.basicConfig(filename=log_file, encoding='utf-8', level=log_level, format=log_format,
                        datefmt='%FT%T%z')

    sim = RaceCaptureSim(args.config)
    if not sim.load():
        sys.exit(1)

    sim.run()
