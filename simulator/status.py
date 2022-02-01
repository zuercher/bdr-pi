from common import Common
from logging import Logging
from singleton import Singleton
from version import Version

@Singleton
class Status(Logging):
    def __init__(self):
        super().__init__()
        self.common = Common.instance()
        self.version = Version.instance()


    def commands(self):
        return [ 'getStatus' ]


    def execute(self, cmd, query):
        if cmd != 'getStatus':
            return None

        return {
            'status': {
                'system': {
                    'model': self.common.friendly_name(),
                    'uptime': self.common.uptime_s(),
                } | self.version.version_info(),
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
