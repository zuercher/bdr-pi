#include <linux/kernel.h>

#include <linux/net.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/uio.h>
#include <linux/un.h>
#include <net/sock.h>

#include "common.h"
#include "socket.h"

#define SOCKET "bridge-socket: "
#define BUF_SIZE (64*1024)

static char socket_name[26] = BRIDGE_SOCKET_NAME;

int socket_init(struct bridge_socket* s, int (*consume)(void*, void*, int), void* data)
{
  if (s == NULL) {
    return -ENOMEM;
  }

  mutex_init(&s->mutex);

  s->listener = NULL;
  s->accepted = NULL;
  s->buf = kmalloc(BUF_SIZE, GFP_KERNEL);
  s->paused = 0;
  s->pending_data = 0;
  s->consume = consume;
  s->consumer_data = data;

  if (s->buf == NULL) {
    pr_err(SOCKET "failed to allocate recv buffer\n");
    return -ENOMEM;
  }

  return 0;
}

static void socket_read_handler(struct bridge_socket* s) {
  struct kvec iov[1] = { 0 };
  struct msghdr msg = { .msg_flags = MSG_NOSIGNAL };

  int rc;

  iov[0].iov_base = s->buf;
  iov[0].iov_len = BUF_SIZE;

  mutex_lock(&s->mutex);
  if (s->accepted == NULL) {
    goto done;
  }

  if (s->paused) {
    s->pending_data = 1;
    goto done;
  }

  // TODO: if pending_data was set we should check that we read all the data (may need to MSG_PEEK)
  rc = kernel_recvmsg(s->accepted, &msg, iov, 1, BUF_SIZE, msg.msg_flags);
  if (rc > 0) {
    s->pending_data = 0;
    rc = s->consume(s->consumer_data, s->buf, rc);
    if (rc < 0) {
      pr_err(SOCKET "consume error %d\n", rc);
    }
  } else if (rc < 0 && rc != -EAGAIN) {
    pr_err(SOCKET "read error %d\n", rc);
  }

 done:
  mutex_unlock(&s->mutex);
}

static void socket_read_handler_cb(struct sock* sk) {
  struct bridge_socket* s = (struct bridge_socket*)sk->sk_user_data;
  socket_read_handler(s);
}
static void socket_state_handler(struct sock* sk) {
  struct bridge_socket* s = (struct bridge_socket*)sk->sk_user_data;

  mutex_lock(&s->mutex);

  switch (sk->sk_state) {
  case TCP_CLOSE:
    fallthrough;
  case TCP_CLOSE_WAIT:
    if (s->accepted != NULL) {
      pr_info(SOCKET "conn closed\n");
      sock_release(s->accepted);
      s->accepted = NULL;
    }
    break;
  default:
    // don't care
    break;
  }

  mutex_unlock(&s->mutex);
}

static void socket_accept_handler(struct sock* sk) {
  struct bridge_socket* s;
  struct socket* conn = NULL;
  int rc = sock_create_lite(AF_UNIX, SOCK_STREAM, 0, &conn);
  if (rc < 0) {
    pr_err(SOCKET "failed to create accept socket: %d\n", rc);
    return;
  }

  s = (struct bridge_socket*)sk->sk_user_data;

  mutex_lock(&s->mutex);
  if (s->accepted != NULL) {
    pr_info(SOCKET "closing stale connection\n");
    sock_release(s->accepted);
    s->accepted = NULL;
  }

  conn->type = s->listener->type;
  conn->ops = s->listener->ops;

  rc = s->listener->ops->accept(s->listener, conn, 0, true);
  if (rc < 0) {
    pr_err(SOCKET "failed to accept connection: %d\n", rc);
    sock_release(conn);
    goto done;
  }

  s->accepted = conn;

  conn->sk->sk_user_data = s;
  conn->sk->sk_data_ready = socket_read_handler_cb;

 done:
  mutex_unlock(&s->mutex);
}

int socket_listen(struct bridge_socket* s)
{
  struct sockaddr_un addr;
  size_t addrlen;
  int rc;

  if (s == NULL) {
    return -EINVAL;
  }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path+1, socket_name+1, sizeof(addr.sun_path) - 2);
  addrlen = offsetof(struct sockaddr_un, sun_path)+BRIDGE_SOCKET_NAME_LEN;

  rc = sock_create(AF_UNIX, SOCK_STREAM, 0, &s->listener);
  if (rc < 0) {
    pr_err(SOCKET "failed to open socket: %d\n", rc);
    return rc;
  }

  s->listener->sk->sk_user_data = s;
  s->listener->sk->sk_data_ready = socket_accept_handler;
  s->listener->sk->sk_state_change = socket_state_handler;

  rc = s->listener->ops->bind(s->listener, (struct sockaddr*)&addr, addrlen);
  if (rc < 0) {
    pr_err(SOCKET "failed to bind socket: %d\n", rc);
    sock_release(s->listener);
    s->listener = NULL;
    return rc;
  }

  rc = s->listener->ops->listen(s->listener, 1);
  if (rc < 0) {
    pr_err(SOCKET "failed to listener on socket: %d\n", rc);
    sock_release(s->listener);
    s->listener = NULL;
    return rc;
  }

  return 0;
}

int socket_close(struct bridge_socket* s)
{
  if (s == NULL) {
    return 0;
  }

  mutex_lock(&s->mutex);
  s->paused = 0;

  if (s->accepted != NULL) {
    struct socket* a = s->accepted;
    s->accepted = NULL;
    sock_release(a);
  }

  if (s->listener != NULL) {
    struct socket* l = s->listener;
    s->listener = NULL;
    sock_release(l);
  }

  if (s->buf != NULL) {
    kfree(s->buf);
  }

  mutex_unlock(&s->mutex);

  return 0;
}

int socket_write(struct bridge_socket* s, void* data, int len) {
  struct kvec iov[1] = { 0 };
  struct msghdr msg = { .msg_flags = MSG_NOSIGNAL };
  int rc;

  mutex_lock(&s->mutex);

  if (s->accepted != NULL) {
    iov[0].iov_base = data;
    iov[0].iov_len = len;

    rc = kernel_sendmsg(s->accepted, &msg, iov, 1, len);
    if (rc < 0) {
      if (rc != -EPIPE) {
        pr_err(SOCKET "send error %d\n", rc);
      } else {
        rc = 0;
      }

      sock_release(s->accepted);
      s->accepted = NULL;
    }
  } else {
    pr_err(SOCKET "no socket\n");
    rc = -EINVAL;
  }

  mutex_unlock(&s->mutex);

  return rc;
}

void socket_pause(struct bridge_socket* s) {
  mutex_lock(&s->mutex);
  s->paused = 1;
  mutex_unlock(&s->mutex);
}

void socket_resume(struct bridge_socket* s) {
  int call_read_handler = 0;

  mutex_lock(&s->mutex);
  s->paused = 0;
  if (s->accepted != NULL && s->pending_data) {
    call_read_handler = 1;
  }
  mutex_unlock(&s->mutex);

  if (call_read_handler) {
    socket_read_handler(s);
  }
}
