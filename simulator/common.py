import time
from logging import Logging
from singleton import Singleton

@Singleton
class Common(Logging):
    def __init__(self):
        super().__init__()
        self.start = time.monotonic_ns()

    def commands(self):
        return None

    def execute(self):
        return None

    def friendly_name(self):
        return 'RaceCapture/Pro MK3'

    def start_time(self):
        return self.start

    def uptime_s(self):
        delta = time.monotonic_ns() - self.start_time()
        return delta // 1000000000
