from logging import Logging
from singleton import Singleton

class LoggerMessage:
    def __init__(self, msg_type, ticks = 0, sample = None, needs_meta = False):
        self.msg_type = msg_type
        self.ticks = ticks
        self.sample = sample
        self.needs_meta = needs_meta

    def as_dict(self):
        return {

        }

@Singleton
class Telemetry(Logging):
    MessageType_Sample = 0
    MessageType_Start = 1
    MessageType_Stop = 2

    def __init__(self):
        super().__init__()
        self.rate = 0


    def commands(self):
        return [ 'setTelemetry']


    def execute(self, cmd, query):
        if cmd != 'setTelemetry':
            return None

        self.rate = query['rate']
        self.print(1, 'telemetry rate:', self.rate)

        // If > 0 need to start logging sample
        // If <= 0 need to stop

        // See loggerTaskEx.c

        return {}
