from logging import Logging
from singleton import Singleton

class Sample:
    def __init__(self, ticks, channel_count, channel_samples)

    def as_dict(self):
        resp = {
            't': ticks,
        }

        if ticks == 0:
            resp['meta'] = [
                # N channel configs
            ]

        resp['d'] = [
            # N channel values of (float, int, long long double)
            # followed by M = ((N // 32) + 1) ints. Each int's bits represent one of the N
            # channels indicating if the channel was sampled. Bit 0 of the first int is the
            # first channel, bit 1 is the second, ...

            # see loggerSampleData.c init_channel_sample_buffer for where each channel comes from
        ]

        return {'s': resp}

@Singleton
class Telemetry(Logging):
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

        // If > 0 need to start logging samples
        // If <= 0 need to stop

        // See loggerTaskEx.c

        return {}
