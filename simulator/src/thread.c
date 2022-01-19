#include <linux/kernel.h>
#include <linux/kthread.h>

#include <linux/net.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/uio.h>
#include <linux/un.h>

#include "common.h"
#include "thread.h"

#define THREAD "bridge-thread: "
#define BUF_SIZE (4*1024)

static char thread_name[11] = "bridge_tty";
static char socket_name[26] = BRIDGE_SOCKET_NAME;

int thread_init(struct bridge_thread* t, int (*consume)(void*, void*, int), void* data)
{
  if (t == NULL) {
    return -ENOMEM;
  }

  mutex_init(&t->mutex);

  t->thread = NULL;
  t->listener = NULL;
  t->accepted = NULL;
  t->paused = 0;
  t->quit = 0;

  t->consume = consume;
  t->consumer_data = data;

  return 0;
}

static int thread_should_quit(struct bridge_thread* t)
{
  int rc;
  mutex_lock(&t->mutex);
  rc = t->quit;
  mutex_unlock(&t->mutex);
  return rc;
}

static int thread_paused(struct bridge_thread* t)
{
  int rc;
  mutex_lock(&t->mutex);
  rc = t->paused;
  mutex_unlock(&t->mutex);
  return rc;
}

static void thread_set_listener(struct bridge_thread* t, struct socket *listener)
{
  mutex_lock(&t->mutex);
  t->listener = listener;
  mutex_unlock(&t->mutex);
}

static void thread_set_accepted(struct bridge_thread* t, struct socket *accepted)
{
  mutex_lock(&t->mutex);
  t->accepted = accepted;
  mutex_unlock(&t->mutex);
}

static int thread_read_loop(struct bridge_thread* t)
{
  void* buf;
  int rc;

  buf = kmalloc(BUF_SIZE, GFP_KERNEL);
  if (buf == NULL) {
    printk(KERN_ERR THREAD "failed to allocate recv buffer");
    return -ENOMEM;
  }

  while (!thread_should_quit(t) && !kthread_should_stop()) {
    struct iovec iov = { 0 };
    struct msghdr msg = { 0 };

    if (thread_paused(t)) {
      // Sleep for 100ms
      schedule_timeout(HZ / 10);
      continue;
    }

    iov.iov_base = buf;
    iov.iov_len = BUF_SIZE;
    iov_iter_init(&msg.msg_iter, READ, &iov, 1, 1);

    rc = sock_recvmsg(t->accepted, &msg, 0);
    if (rc <= 0) {
      if (rc == -EAGAIN) {
        // Retry on EGAIN.
        continue;
      }
      // Error or closed.
      if (rc < 0) {
        printk(KERN_ERR THREAD "read error %d", rc);
      } else {
        printk(KERN_INFO THREAD "connection closed");
      }

      break;
    }

    rc = t->consume(t->consumer_data, buf, rc);
    if (rc < 0) {
      printk(KERN_ERR THREAD "consume error %d", rc);
      break;
    }
  }

  kfree(buf);

  return rc;
}

static int thread_fn(void* data)
{
  struct socket* listener = NULL;
  struct sockaddr_un addr;
  int rc;

  struct bridge_thread* t = (struct bridge_thread*)data;
  if (t == NULL) {
    return -EINVAL;
  }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_name, sizeof(addr.sun_path) - 1);

  rc = sock_create(AF_UNIX, SOCK_STREAM, 0, &listener);
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to open socket: %d", rc);
    return rc;
  }

  rc = listener->ops->bind(listener, (struct sockaddr*)&addr, sizeof(addr));
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to bind socket: %d", rc);
    sock_release(listener);
    return rc;
  }

  rc = listener->ops->listen(listener, 1);
  if (rc < 0) {
    printk(KERN_ERR THREAD "failed to listener on socket: %d", rc);
    sock_release(listener);
    return rc;
  }

  thread_set_listener(t, listener);

  while (!thread_should_quit(t) && !kthread_should_stop()) {
    struct socket* conn = NULL;
    rc = sock_create_lite(AF_UNIX, SOCK_STREAM, 0, &conn);
    if (rc < 0) {
      printk(KERN_ERR THREAD "failed to create accept socket: %d", rc);
      break;
    }
    conn->type = listener->type;
    conn->ops = listener->ops;

    rc = listener->ops->accept(listener, conn, 0, true);
    if (rc < 0) {
      printk(KERN_ERR THREAD "failed to accept connection: %d", rc);
      sock_release(conn);
      break;
    }

    thread_set_accepted(t, conn);

    rc = thread_read_loop(t);

    thread_set_accepted(t, NULL);
    sock_release(conn);

    if (rc < 0) {
      printk(KERN_ERR THREAD "read loop failed, exiting");
      break;
    }
  }

  thread_set_listener(t, NULL);
  sock_release(listener);

  return rc;
}

int thread_start(struct bridge_thread* t)
{
  int rc = 0;

  if (t == NULL) {
    return -EINVAL;
  }

  mutex_lock(&t->mutex);

  if (t->thread != NULL) {
    printk(KERN_ERR "start: unitialized thread");
    rc = -EINVAL;
    goto exit;
  }

  t->thread = kthread_run(thread_fn, t, thread_name);
  if (IS_ERR(t->thread)) {
    rc = PTR_ERR(t->thread);
    printk(KERN_ERR "start: failed to run thread: %d", rc);
    goto exit;
  }

 exit:
  mutex_unlock(&t->mutex);
  return rc;
}

int thread_stop(struct bridge_thread* t)
{
  int rc = 0;
  int try_stop = 0;

  if (t == NULL) {
    return 0;
  }

  mutex_lock(&t->mutex);
  if (t->thread == NULL) {
    printk(KERN_ERR "stop: unitialized thread");
    rc = 0;
    goto release;
  }

  t->quit = 1;
  t->paused = 0;
  try_stop = 1;

  // Knock the thread out of read/accept.
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

 release:
  mutex_unlock(&t->mutex);

  if (try_stop) {
    rc = kthread_stop(t->thread);
  }

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
