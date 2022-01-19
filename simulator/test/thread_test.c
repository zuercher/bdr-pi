#include <linux/module.h>
#include <linux/net.h>
#include <linux/slab.h>
#include <linux/timer.h>
#include <linux/uio.h>

#include "thread.h"

struct bridge_thread thread;

#define THREAD_TEST "thread_test: "
#define DUMP_FMT_PREFIX THREAD_TEST "received "
#define DUMP_FMT DUMP_FMT_PREFIX "%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %s"

#define TIMER "timer: "

struct thread_test {
  struct timer_list *timer;
  int timer_count;
  void* wbuf;
};

static struct thread_test* g_thread_test = NULL;
static struct bridge_thread *g_thread = NULL;

static int thread_test_consumer(void *ctxt, void* data, int len)
{
  unsigned char* bytes = (unsigned char*)data;
  unsigned char copy[16] = { 0 };
  char readable[17] = { 0 };
  int i, j;

  printk(KERN_INFO THREAD_TEST "received %d bytes:", len);

  for(i = 0; i < len; i += 16) {
    if (i + 16 <= len) {
      memcpy(readable, bytes, 16);
      memcpy(copy, bytes, 16);
      for(j = 0; j < 16; j++) {
        if (readable[j] < 0x20 || readable[j] > 0x7E) {
          readable[j] = '.';
        }
      }
    } else {
      // short, only do the available part
      memset(readable, 0, 17);
      memcpy(copy, bytes + i, len - i);
      memcpy(readable, bytes + i, len - i);
      for(j = 0; j < 16; j++) {
        if (j >= len - i) {
          readable[j] = ' ';
        } else if (readable[j] < 0x20 || readable[j] > 0x7E) {
          readable[j] = '.';
        }
      }
    }

    printk(KERN_INFO DUMP_FMT,
           copy[i+0], copy[i+1], copy[i+2], copy[i+3],
           copy[i+4], copy[i+5], copy[i+6], copy[i+7],
           copy[i+8], copy[i+9], copy[i+10], copy[i+11],
           copy[i+12], copy[i+13], copy[i+14], copy[i+15],
           readable);
  }

  if (g_thread_test != NULL) {
    mod_timer(g_thread_test->timer, jiffies + msecs_to_jiffies(100));
  }

  return 0;
}

static void thread_test_timer(struct timer_list* timer) {
  int len;

  if (g_thread == NULL) {
    printk(KERN_ERR THREAD_TEST TIMER "no thread");
    return;
  }

  len = sprintf(g_thread_test->wbuf, "TOCK %d\n", ++g_thread_test->timer_count);

  if (thread_write(g_thread, g_thread_test->wbuf, len) == 0) {
    printk(KERN_ERR THREAD_TEST TIMER "no socket");
  }
}

int thread_test_init (void) {
  int rc;

  g_thread = kmalloc(sizeof(*g_thread), GFP_KERNEL);
  if (!g_thread) {
    printk(KERN_ERR THREAD_TEST "failed to allocate thread");
    return -ENOMEM;
  }

  g_thread_test = kmalloc(sizeof(*g_thread_test), GFP_KERNEL);
  if (!g_thread_test) {
    printk(KERN_ERR THREAD_TEST "failed to allocate test data");
    kfree(g_thread);
    g_thread = NULL;
    return -ENOMEM;
  }

  g_thread_test->wbuf = kmalloc(128, GFP_KERNEL);
  if (!g_thread_test->wbuf) {
    printk(KERN_ERR THREAD_TEST "failed to allocate thread buffer");
    kfree(g_thread);
    return -ENOMEM;
  }
  memset(g_thread_test->wbuf, 0, 128);

  g_thread_test->timer_count = 0;
  g_thread_test->timer = kmalloc(sizeof(*g_thread_test->timer), GFP_KERNEL);
  if (!g_thread_test->timer) {
    printk(KERN_ERR THREAD_TEST "failed to allocate timer");

    kfree(g_thread);
    g_thread = NULL;
    kfree(g_thread_test);
    g_thread_test = NULL;

    return -ENOMEM;
  }

  rc = thread_init(g_thread, thread_test_consumer, NULL);
  if (rc < 0) {
    printk(KERN_ERR THREAD_TEST "failed to initialize thread");

    kfree(g_thread);
    g_thread = NULL;
    kfree(g_thread_test->timer);
    kfree(g_thread_test);
    g_thread_test = NULL;

    return rc;
  }

  rc = thread_start(g_thread);
  if (rc < 0) {
    printk(KERN_ERR THREAD_TEST "failed to start thread");

    kfree(g_thread);
    g_thread = NULL;
    kfree(g_thread_test->timer);
    kfree(g_thread_test);
    g_thread_test = NULL;

    return rc;
  }

  timer_setup(g_thread_test->timer, thread_test_timer, 0);

  printk(KERN_INFO THREAD_TEST "initialized");

  return 0;
}

void thread_test_exit(void) {
  int rc;

  printk(KERN_INFO THREAD_TEST "exiting");
  if (g_thread != NULL) {
    rc = thread_stop(g_thread);
    if (rc < 0) {
      printk(KERN_ERR THREAD_TEST "failed to stop thread %d", rc);
    }

    kfree(g_thread);
    g_thread = NULL;
  }

  if (g_thread_test != NULL) {
    if (g_thread_test->timer != NULL) {
      del_timer(g_thread_test->timer);
      kfree(g_thread_test->timer);
      kfree(g_thread_test->wbuf);
    }

    kfree(g_thread_test);
    g_thread_test = NULL;
  }

  printk(KERN_INFO THREAD_TEST "completed");
}

#define DRIVER_VERSION "v0.1"
#define DRIVER_AUTHOR "Stephan Zuercher <zuercher@gmail.com>"
#define DRIVER_DESC "Thread Testing Thingy"

MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);

module_init(thread_test_init);
module_exit(thread_test_exit);
