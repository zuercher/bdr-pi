#include <linux/kernel.h>

#include <linux/net.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/uio.h>
#include <linux/un.h>
#include <net/sock.h>

#include "common.h"
#include "thread.h"

#define THREAD "bridge-thread: "
#define BUF_SIZE (4*1024)

static char socket_name[26] = BRIDGE_SOCKET_NAME;

int thread_init(struct bridge_thread* t, int (*consume)(void*, void*, int), void* data)
{
  if (t == NULL) {
    return -ENOMEM;
  }

  mutex_init(&t->mutex);

  t->listener = NULL;
  t->accepted = NULL;
  t->buf = kmalloc(BUF_SIZE, GFP_KERNEL);
  t->paused = 0;
  t->consume = consume;
  t->consumer_data = data;

  if (t->buf == NULL) {
    printk(KERN_ERR THREAD "failed to allocate recv buffer");
    return -ENOMEM;
  }

  return 0;
}

static void thread_read_handler(struct sock* sk) {
  struct bridge_thread* t = (struct bridge_thread*)sk->sk_user_data;
  struct kvec iov[1] = { 0 };
  struct msghdr msg = { .msg_flags = MSG_NOSIGNAL };

  int rc;

  iov[0].iov_base = t->buf;
  iov[0].iov_len = BUF_SIZE;

  mutex_lock(&t->mutex);
  if (t->paused) {
    // TODO: Remember there's data ready and call handler from unpause?
    goto done;
  }

  rc = kernel_recvmsg(t->accepted, &msg, iov, 1, BUF_SIZE, msg.msg_flags);
  if (rc > 0) {
    rc = t->consume(t->consumer_data, t->buf, rc);
    if (rc < 0) {
      printk(KERN_ERR THREAD "consume error %d", rc);
    }
  } else if (rc < 0 && rc != -EAGAIN) {
    printk(KERN_ERR THREAD "read error %d", rc);
  }

 done:
  mutex_unlock(&t->mutex);
}

static void thread_state_handler(struct sock* sk) {
  struct bridge_thread* t = (struct bridge_thread*)sk->sk_user_data;

  mutex_lock(&t->mutex);

  switch (sk->sk_state) {
  case TCP_CLOSE:
    fallthrough;
  case TCP_CLOSE_WAIT:
    if (t->accepted != NULL) {
      printk(KERN_INFO THREAD "conn closed");
      sock_release(t->accepted);
      t->accepted = NULL;
    }
    break;
  default:
    // don't care
    break;
  }

  mutex_unlock(&t->mutex);
}

static void thread_accept_handler(struct sock* sk) {
  struct bridge_thread* t;
  struct socket* conn = NULL;
  int rc = sock_create_lite(AF_UNIX, SOCK_STREAM, 0, &conn);
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to create accept socket: %d", rc);
    return;
  }

  t = (struct bridge_thread*)sk->sk_user_data;

  mutex_lock(&t->mutex);
  if (t->accepted != NULL) {
    printk(KERN_INFO THREAD "closing stale connection");
    sock_release(t->accepted);
    t->accepted = NULL;
  }

  conn->type = t->listener->type;
  conn->ops = t->listener->ops;

  rc = t->listener->ops->accept(t->listener, conn, 0, true);
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to accept connection: %d", rc);
    sock_release(conn);
    goto done;
  }

  t->accepted = conn;

  conn->sk->sk_user_data = t;
  conn->sk->sk_data_ready = thread_read_handler;

 done:
  mutex_unlock(&t->mutex);
}

static int thread_listen(struct bridge_thread* t)
{
  struct sockaddr_un addr;
  int rc;

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_name, sizeof(addr.sun_path) - 1);

  rc = sock_create(AF_UNIX, SOCK_STREAM, 0, &t->listener);
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to open socket: %d", rc);
    return rc;
  }

  t->listener->sk->sk_user_data = t;
  t->listener->sk->sk_data_ready = thread_accept_handler;
  t->listener->sk->sk_state_change = thread_state_handler;

  rc = t->listener->ops->bind(t->listener, (struct sockaddr*)&addr, sizeof(addr));
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to bind socket: %d", rc);
    sock_release(t->listener);
    t->listener = NULL;
    return rc;
  }

  rc = t->listener->ops->listen(t->listener, 1);
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to listener on socket: %d", rc);
    sock_release(t->listener);
    t->listener = NULL;
    return rc;
  }

  return 0;
}

int thread_start(struct bridge_thread* t)
{
  if (t == NULL) {
    return -EINVAL;
  }

  return thread_listen(t);
}

int thread_stop(struct bridge_thread* t)
{
  if (t == NULL) {
    return 0;
  }

  mutex_lock(&t->mutex);
  t->paused = 0;

  if (t->accepted != NULL) {
    struct socket* s = t->accepted;
    t->accepted = NULL;
    sock_release(s);
  }

  if (t->listener != NULL) {
    struct socket* s = t->listener;
    t->listener = NULL;
    sock_release(s);
  }

  mutex_unlock(&t->mutex);

  return 0;
}

int thread_write(struct bridge_thread* t, void* data, int len) {
  struct kvec iov[1] = { 0 };
  struct msghdr msg = { .msg_flags = MSG_NOSIGNAL };
  int rc;

  mutex_lock(&t->mutex);

  if (t->accepted != NULL) {
    iov[0].iov_base = data;
    iov[0].iov_len = len;

    rc = kernel_sendmsg(t->accepted, &msg, iov, 1, len);
    if (rc < 0) {
      if (rc != -EPIPE) {
        printk(KERN_ERR THREAD "send error %d", rc);
      } else {
        rc = 0;
      }

      sock_release(t->accepted);
      t->accepted = NULL;
    }
  } else {
    printk(KERN_ERR THREAD "no socket");
    rc = 0;
  }

  mutex_unlock(&t->mutex);

  return rc;
}

void thread_pause(struct bridge_thread* t) {
  mutex_lock(&t->mutex);
  t->paused = 1;
  mutex_unlock(&t->mutex);
}

void thread_unpause(struct bridge_thread* t) {
  mutex_lock(&t->mutex);
  t->paused = 0;
  mutex_unlock(&t->mutex);
}
