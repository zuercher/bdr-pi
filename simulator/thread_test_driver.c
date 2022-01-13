#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "common.h"

static char socket_name[26] = BRIDGE_SOCKET_NAME;

int main(int argc, char** argv) {
  struct sockaddr_un addr;
  int sfd, rc;
  ssize_t len;
  char *buf;

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_name, sizeof(addr.sun_path) - 1);

  sfd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sfd == 0) {
    printf("error: could not open socket %d (%s)\n", errno, strerror(errno));
    return 1;
  }

  rc = connect(sfd, (struct sockaddr*)&addr, sizeof(addr));
  if (rc != 0) {
    printf("error: could not connect socket %d (%s)\n", errno, strerror(errno));
    close(sfd);
    return 1;
  }

  buf = "XYZPDQ";
  len = write(sfd, buf, strlen(buf));
  if (len != strlen(buf)) {
    printf("warning: short write (%d vs %d)\n", (int)len, strlen(buf));
  }

  sleep(5);

  buf = "I\nthink\nthis\nshould\nbe\nok\n\nreally\n";
  len = write(sfd, buf, strlen(buf));
  if (len != strlen(buf)) {
    printf("warning: short write (%d vs %d)\n", (int)len, strlen(buf));
  }

  close(sfd);
  return 0;
}
