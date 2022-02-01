from logging import Logging
from singleton import Singleton

class ChannelConfig:
    TICK_RATE_HZ = 1000 # 1000 ticks/s = 1 tick/ms

    SAMPLE_1000Hz = (TICK_RATE_HZ / 1000)
    SAMPLE_500Hz  = (TICK_RATE_HZ / 500)
    SAMPLE_200Hz  = (TICK_RATE_HZ / 200)
    SAMPLE_100Hz  = (TICK_RATE_HZ / 100)
    SAMPLE_50Hz   = (TICK_RATE_HZ / 50)
    SAMPLE_25Hz   = (TICK_RATE_HZ / 25)
    SAMPLE_10Hz   = (TICK_RATE_HZ / 10)
    SAMPLE_5Hz    = (TICK_RATE_HZ / 5)
    SAMPLE_1Hz    = (TICK_RATE_HZ / 1)


    def __init__(self, label, units = '', fmin = 0.0, fmax = 0.0, sample_rate = 0, precision = 0,
                 flags = 0):
        self.label = label
        self.units = units
        self.fmin = fmin
        self.fmax = fmax
        self.sample_rate = sample_rate # ticks per sample
        self.precision = precision
        self.flags = flags


    def as_dict(self):
        # convert to sample rate in ticks/sample
        sr = 0
        if self.sample_rate > 0 and self.sample_rate < self.TICK_RATE_HZ:
            sr = self.TICK_RATE_HZ / self.sample_rate

        return {
            'nm': self.label,
            'ut': self.units,
            'min': round(self.fmin, self.precision),
            'max': round(self.fmax, self.precision),
            'prec': self.precision,
            'sr': sr
        }

@Singleton
class LapConfig(Logging):
    DEFAULT_LAP_STATS_SAMPLE_RATE = ChannelConfig.SAMPLE_10Hz

    def __init__(self):
        super().__init__()
        self.lap_count = ChannelConfig('LapCount', sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE)
        self.lap_time = ChannelConfig('LapTime', units="Min",
                                      sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE, precision=4)
        self.sector = ChannelConfig('Sector', sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE)
        self.sector_time = ChannelConfig('SectorTime', units='Min',
                                         sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE,
                                         precision=4)
        self.pred_time = ChannelConfig('PredTime', units='Min',
                                       sample_rate=ChannelConfig.SAMPLE_5Hz, precision=4)
        self.elapsed_time = ChannelConfig('ElapsedTime', units='Min',
                                          sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE,
                                          precision=4)
        self.current_lap = ChannelConfig('CurrentLap',
                                         sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE)
        self.distance = ChannelConfig('Distance', units='mi',
                                      sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE, precision=4)
        self.session_time = ChannelConfig('SessionTime', units='Min',
                                          sample_rate=self.DEFAULT_LAP_STATS_SAMPLE_RATE,
                                          precision=4)

    def commands(self):
        return [ 'getLapCfg']


    def execute(self, cmd, query):
        if cmd != 'getLapCfg':
            return None

        return {
            'lapCfg': {
                'lapCount': self.lap_count.as_dict(),
                'lapTime': self.lap_time.as_dict(),
                'predTime': self.pred_time.as_dict(),
                'sector': self.sector.as_dict(),
                'sectorTime': self.sector_time.as_dict(),
                'elapsedTime': self.elapsed_time.as_dict(),
                'currentLap': self.current_lap.as_dict(),
                'dist': self.distance.as_dict(),
                'sessionTime': self.session_time.as_dict(),
            }
        }
