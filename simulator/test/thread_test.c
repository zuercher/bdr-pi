#include <linux/module.h>
#include <linux/net.h>
#include <linux/slab.h>
#include <linux/timer.h>
#include <linux/uio.h>

#include "thread.h"

struct bridge_thread thread;

#define DUMP_FMT_PREFIX "thread_test: received "
#define DUMP_FMT DUMP_FMT_PREFIX "%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %s"

#define TIMER "timer: "

static struct thread_test {
  struct bridge_thread thread;

  struct timer_list *timer;
  int timer_count;
} thread_test;

static int thread_test_consumer(void *ctxt, void* data, int len)
{
  unsigned char* bytes = (unsigned char*)data;
  unsigned char copy[16] = { 0 };
  char readable[17] = { 0 };
  int i, j;
  for(i = 0; i < len; i += 16) {
    memcpy(readable, bytes, 16);
    for(j = 0; j < 16; j++) {
      if (readable[j] < 0x32 || readable[j] > 0x7E) {
        readable[j] = '.';
      }
    }
    printk(KERN_INFO DUMP_FMT,
           bytes[i+0], bytes[i+1], bytes[i+2], bytes[i+3],
           bytes[i+4], bytes[i+5], bytes[i+6], bytes[i+7],
           bytes[i+8], bytes[i+9], bytes[i+10], bytes[i+11],
           bytes[i+12], bytes[i+13], bytes[i+14], bytes[i+15],
           readable);
  }

  memset(readable, 0, 17);
  memcpy(copy, bytes + i, len - i);
  memcpy(readable, bytes + i, len - i);
  for(j = 0; j < 16; j++) {
    if (j > len - i) {
      readable[j] = ' ';
    } else if (readable[j] < 0x32 || readable[j] > 0x7E) {
      readable[j] = '.';
    }
  }
  printk(KERN_INFO DUMP_FMT,
         copy[i+0], copy[i+1], copy[i+2], copy[i+3],
         copy[i+4], copy[i+5], copy[i+6], copy[i+7],
         copy[i+8], copy[i+9], copy[i+10], copy[i+11],
         copy[i+12], copy[i+13], copy[i+14], copy[i+15],
         readable);

  return 0;
}

static void thread_test_timer(struct timer_list* timer) {
  struct iovec iov = { 0 };
  struct msghdr msg = { 0 };
  struct socket* accepted;
  char buf[128];
  int rc;
  sprintf(buf, "TICK %d\n", ++thread_test.timer_count);
  iov.iov_base = buf;
  iov.iov_len = strlen(buf);
  iov_iter_init(&msg.msg_iter, WRITE, &iov, 1, 1);

  mutex_lock(&thread_test.thread.mutex);
  accepted = thread_test.thread.accepted;
  mutex_unlock(&thread_test.thread.mutex);

  if (accepted == NULL) {
    return;
  }

  rc = sock_sendmsg(accepted, &msg);
  if (rc < 0) {
    printk(KERN_ERR TIMER "send error %d", -rc);
  }

  timer->expires = jiffies + HZ;
  add_timer(timer);
}

int thread_test_init (void) {
  int rc = thread_init(&thread_test.thread, thread_test_consumer, NULL);
  if (rc < 0) {
    printk(KERN_ERR "failed to initialize thread");
    return rc;
  }

  rc = thread_start(&thread_test.thread);
  if (rc < 0) {
    printk(KERN_ERR "failed to start thread");
    return rc;
  }

  thread_test.timer = kmalloc(sizeof(*thread_test.timer), GFP_KERNEL);
  if (!thread_test.timer) {
    printk(KERN_ERR "failed to allocate timer");

    thread_stop(&thread_test.thread);

    return -ENOMEM;
  }

  timer_setup(thread_test.timer, thread_test_timer, 0);
  thread_test.timer->expires = jiffies + HZ;
  add_timer(thread_test.timer);

  return 0;
}

void thread_test_exit(void) {
  int rc;

  if (thread_test.timer != NULL) {
    del_timer(thread_test.timer);
  }

  rc = thread_stop(&thread);
  if (rc < 0) {
    printk(KERN_ERR "failed to stop thread");
  }
}

#define DRIVER_VERSION "v0.1"
#define DRIVER_AUTHOR "Stephan Zuercher <zuercher@gmail.com>"
#define DRIVER_DESC "Thread Testing Thingy"

MODULE_LICENSE("Apache-2.0");
MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);

module_init(thread_test_init);
module_exit(thread_test_exit);
