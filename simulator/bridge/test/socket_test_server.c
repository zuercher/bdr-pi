#include <stdio.h>
#include <stddef.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "common.h"

// socket_test_server simulates the kernel module in socket_test.c. It
// listens on BRIDGE_SOCKET_NAME and accepts a connection.  It reads
// data from the socket, and responds by replacing the first 4
// characters with "TOCK" (or replacing the entire message with
// "TOCK\n" if it's too short). After 10 iteations the socket is
// closed and the server returns to the listening state.

static char socket_name[26] = BRIDGE_SOCKET_NAME;

void usage(const char* argv0) {
  printf("usage: %s\n", argv0);
  printf("\n");
  printf("Simulates the socket_test kernel module in user space for testing the\n");
  printf("socket_test_driver.\n");
  exit(1);
}

static char buffer[4096];

int main(int argc, char** argv) {
  struct sockaddr_un addr;
  socklen_t addrlen;
  int lfd, rc;
  ssize_t len;
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

  lfd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (lfd == 0) {
    printf("server: error: could not open socket %d (%s)\n", errno, strerror(errno));
    return 1;
  }

  rc = bind(lfd, (struct sockaddr*)&addr, addrlen);
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

    for(int tick = 0; tick < 10; tick++) {
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

    printf("server: closing\n");
    close(sfd);
  }

  close(lfd);
  return 0;
}
