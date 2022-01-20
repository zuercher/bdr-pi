#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "common.h"

static char socket_name[26] = BRIDGE_SOCKET_NAME;

void usage(const char* argv0) {
  printf("usage: %s [--tick | --tock]\n", argv0);
  printf("\n");
  printf("Sends messages to the bridge socket for testing with the sockettest\n");
  printf("kernel module.\n");
  exit(1);
}

static char buffer[4096];

int main(int argc, char** argv) {
  struct sockaddr_un addr;
  int sfd, rc;
  ssize_t len;
  int tick;
  if (argc != 2) {
    usage(argv[0]);
  }

  if (!strcmp(argv[1], "--tick")) {
    tick = 1;
  } else if (!strcmp(argv[1], "--tock")) {
    tick = 0;
  } else {
    usage(argv[0]);
  }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_name, sizeof(addr.sun_path) - 1);

  sfd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sfd == 0) {
    printf("driver: error: could not open socket %d (%s)\n", errno, strerror(errno));
    return 1;
  }

  rc = connect(sfd, (struct sockaddr*)&addr, sizeof(addr));
  if (rc != 0) {
    printf("driver: error: could not connect socket %d (%s)\n", errno, strerror(errno));
    close(sfd);
    return 1;
  }

  if (tick) {
    tick = 0;
    for(;;) {
      tick++;
      sprintf(buffer, "TICK %d\n", tick);

      printf("driver: send %s", buffer);
      len = send(sfd, buffer, strlen(buffer), MSG_NOSIGNAL);
      if (len < 0) {
        if (errno == EPIPE) {
          printf("driver: got remote close\n");
        } else {
          printf("driver: error: send error %d (%s)\n", errno, strerror(errno));
        }
        break;
      }
      if (len < strlen(buffer)) {
        printf("driver: warning: short send (%d vs %d)\n", (int)len, strlen(buffer));
      }

      printf("driver: reading...\n");
      len = read(sfd, buffer, sizeof(buffer)-1);
      if (len < 0) {
        printf("driver: error: read error %d (%s)\n", errno, strerror(errno));
        break;
      } else if (len == 0) {
        printf("driver: got remote close\n");
        break;
      }
      buffer[len] = 0;
      printf("driver: read %d bytes:\n%s\n", len, buffer);

      sleep(1);
    }
  } else {
    for(tick = 0; tick < 10; tick++) {
      printf("driver: reading...\n");
      len = read(sfd, buffer, sizeof(buffer)-1);
      if (len < 0) {
        printf("driver: error: read error %d (%s)\n", errno, strerror(errno));
        break;
      } else if (len == 0) {
        printf("driver: got remote close\n");
        break;
      }
      buffer[len] = 0;
      printf("driver: read %d bytes:\n%s\n", len, buffer);

      if (len > 5) {
        strncpy(buffer, "TOCK", 4);
      } else {
        sprintf(buffer, "TOCK\n");
      }

      printf("driver: send %s", buffer);
      len = send(sfd, buffer, strlen(buffer), MSG_NOSIGNAL);
      if (len < 0) {
        if (errno == EPIPE) {
          printf("driver: got remote close\n");
        } else {
          printf("driver: error: send error %d (%s)\n", errno, strerror(errno));
        }
        break;
      }
      if (len < strlen(buffer)) {
        printf("driver: warning: short send (%d vs %d)\n", (int)len, strlen(buffer));
      }
    }
  }

  printf("driver: closing\n");

  close(sfd);
  return 0;
}
