from logging import Logging
from singleton import Singleton

@Singleton
class Capabilities(Logging):
    def __init__(self):
        super().__init__()


    def commands(self):
        return [ 'getCapabilities']


    def execute(self, cmd, query):
        if cmd != 'getCapabilities':
            return None

        return {
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
