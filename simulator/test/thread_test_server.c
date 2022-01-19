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
  printf("Simulates the thread_test kernel module in user space for testing the\n");
  printf("thread_test_driver.\n");
  exit(1);
}

static char buffer[4096];

int main(int argc, char** argv) {
  struct sockaddr_un addr;
  int lfd, rc;
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

  lfd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (lfd == 0) {
    printf("server: error: could not open socket %d (%s)\n", errno, strerror(errno));
    return 1;
  }

  rc = bind(lfd, (struct sockaddr*)&addr, sizeof(addr));
  if (rc != 0) {
    printf("server: error: could not bind socket %d (%s)\n", errno, strerror(errno));
    close(lfd);
    return 1;
  }

  rc = listen(lfd, 1);
  if (rc != 0) {
    printf("server: error: could not listen on  socket %d (%s)\n", errno, strerror(errno));
    close(lfd);
    return 1;
  }

  for(;;) {
    int sfd = accept(lfd, NULL, NULL);
    if (sfd < 0) {
      printf("server: error: could not accept conn %d (%s)\n", errno, strerror(errno));
      break;
    }

    if (tick) {
      tick = 0;
      for(;;) {
        tick++;
        sprintf(buffer, "TICK %d\n", tick);

        printf("server: send %s", buffer);
        len = send(sfd, buffer, strlen(buffer), MSG_NOSIGNAL);
        if (len < 0) {
          if (errno == EPIPE) {
            printf("server: got remote close\n");
          } else {
            printf("server: error: send error %d (%s)\n", errno, strerror(errno));
          }
          break;
        }
        if (len < strlen(buffer)) {
          printf("server: warning: short write (%d vs %d)\n", (int)len, strlen(buffer));
        }

        printf("server: reading...\n");
        len = read(sfd, buffer, sizeof(buffer)-1);
        if (len < 0) {
          printf("server: error: read error %d (%s)\n", errno, strerror(errno));
          break;
        } else if (len == 0) {
          printf("server: got remote close\n");
          break;
        }
        buffer[len] = 0;
        printf("server: read %d bytes:\n%s\n", len, buffer);

        sleep(1);
      }
    } else {
      for(tick = 0; tick < 10; tick++) {
        printf("server: reading...\n");
        len = read(sfd, buffer, sizeof(buffer)-1);
        if (len < 0) {
          printf("server: error: read error %d (%s)\n", errno, strerror(errno));
          break;
        } else if (len == 0) {
          printf("server: got remote close\n");
          break;
        }
        buffer[len] = 0;
        printf("server: read %d bytes:\n%s\n", len, buffer);

        if (len > 5) {
          strncpy(buffer, "TOCK", 4);
        } else {
          sprintf(buffer, "TOCK\n");
        }

        printf("server: send %s", buffer);
        len = send(sfd, buffer, strlen(buffer), MSG_NOSIGNAL);
        if (len < 0) {
          if (errno == EPIPE) {
            printf("server: got remote close\n");
          } else {
            printf("server: error: send error %d (%s)\n", errno, strerror(errno));
          }
          break;
        }
        if (len < strlen(buffer)) {
          printf("server: warning: short write (%d vs %d)\n", (int)len, strlen(buffer));
        }
      }
      tick = 0;
    }

    printf("server: closing\n");
    close(sfd);
  }

  close(lfd);
  return 0;
}
