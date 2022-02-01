from common import Common
from logging import Logging
from singleton import Singleton

@Singleton
class Version(Logging):
    def __init__(self):
        super().__init__()
        self.common = Common.instance()

    def commands(self):
        return ["getVer"]

    def execute(self, cmd, query):
        if cmd != "getVer":
            return None

        return {
            'ver': {
                'name': 'RCP_MK3',
                'fname': self.common.friendly_name(),
                'release_type': 'RELEASE_TYPE_OFFICIAL',
            } | self.version_info(),
        }

    def version_info(self):
        return {
            'major': 2,
            'minor': 18,
            'bugfix': 4,
            'serial': '1234567890',
            'git_info': '2.18.4',
        }
