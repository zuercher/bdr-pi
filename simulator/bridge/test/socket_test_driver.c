#include <stdio.h>
#include <stddef.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "common.h"

// socket_test_driver tests the socket opened by the module defined in
// socket_test.c. It writes a message of the format "TICK %d\n", waits
// for and prints the response, waits 1 second, and then repeats. If
// the socket is closed, the program exits.

static char socket_name[26] = BRIDGE_SOCKET_NAME;

void usage(const char* argv0) {
  printf("usage: %s\n", argv0);
  printf("\n");
  printf("Sends messages to the bridge socket for testing with the socket_test module.\n");
  printf("kernel module.\n");
  exit(1);
}

static char buffer[4096];

int main(int argc, char** argv) {
  struct sockaddr_un addr;
  socklen_t addrlen;
  int sfd, rc;
  ssize_t len;
  int tick;
  if (argc != 1) {
    usage(argv[0]);
  }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;

  // 1. addr has been zeroed
  // 2. socket_name has a leading zero byte, so we strncpy from socket_name+1
  //    to add.sun_path+1 to preserve it.
  // 3. len(addr.sun_path)-2 to account for the leading null AND to make sure
  //    there's a trailing null, no matter now long socket_name is.
  strncpy(addr.sun_path+1, socket_name+1, sizeof(addr.sun_path) - 2);

  // Set addrlen based on the length of the socket name to avoid a raft of
  // trailing nulls in the socket name.
  addrlen = offsetof(struct sockaddr_un, sun_path)+BRIDGE_SOCKET_NAME_LEN;

  sfd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sfd == 0) {
    printf("driver: error: could not open socket %d (%s)\n", errno, strerror(errno));
    return 1;
  }

  rc = connect(sfd, (struct sockaddr*)&addr, addrlen);
  if (rc != 0) {
    printf("driver: error: could not connect socket %d (%s)\n", errno, strerror(errno));
    close(sfd);
    return 1;
  }

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

  printf("driver: closing\n");

  close(sfd);
  return 0;
}
