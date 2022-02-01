class Logging:
    def __init__(self):
        self.verbosity = 0

    def set_verbosity(self, v):
        self.verbosity = v


    def print(self, level, *parts):
        if level <= self.verbosity:
            print(*parts)


    def error(self, *parts):
        print(*parts)
