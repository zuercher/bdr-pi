#include <linux/module.h>
#include <linux/net.h>
#include <linux/slab.h>
#include <linux/timer.h>
#include <linux/uio.h>

#include "socket.h"

#define SOCKET_TEST "socket_test: "
#define DUMP_FMT_PREFIX SOCKET_TEST "received "
#define DUMP_FMT DUMP_FMT_PREFIX "%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %s"

#define TIMER "timer: "

struct socket_test {
  struct timer_list *timer;
  int timer_count;
  void* wbuf;
};

static struct socket_test* g_socket_test = NULL;
static struct bridge_socket *g_socket = NULL;

static int socket_test_consumer(void *ctxt, void* data, int len)
{
  unsigned char* bytes = (unsigned char*)data;
  unsigned char copy[16] = { 0 };
  char readable[17] = { 0 };
  int i, j;

  printk(KERN_INFO SOCKET_TEST "received %d bytes:", len);

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

  if (g_socket_test != NULL) {
    mod_timer(g_socket_test->timer, jiffies + msecs_to_jiffies(100));
  }

  return 0;
}

static void socket_test_timer(struct timer_list* timer) {
  int len;

  if (g_socket == NULL) {
    printk(KERN_ERR SOCKET_TEST TIMER "no socket");
    return;
  }

  len = sprintf(g_socket_test->wbuf, "TOCK %d\n", ++g_socket_test->timer_count);

  if (socket_write(g_socket, g_socket_test->wbuf, len) == 0) {
    printk(KERN_ERR SOCKET_TEST TIMER "no socket");
  }
}

int socket_test_init (void) {
  int rc;

  g_socket = kmalloc(sizeof(*g_socket), GFP_KERNEL);
  if (!g_socket) {
    printk(KERN_ERR SOCKET_TEST "failed to allocate socket");
    return -ENOMEM;
  }

  g_socket_test = kmalloc(sizeof(*g_socket_test), GFP_KERNEL);
  if (!g_socket_test) {
    printk(KERN_ERR SOCKET_TEST "failed to allocate test data");
    kfree(g_socket);
    g_socket = NULL;
    return -ENOMEM;
  }

  g_socket_test->wbuf = kmalloc(128, GFP_KERNEL);
  if (!g_socket_test->wbuf) {
    printk(KERN_ERR SOCKET_TEST "failed to allocate socket buffer");
    kfree(g_socket);
    return -ENOMEM;
  }
  memset(g_socket_test->wbuf, 0, 128);

  g_socket_test->timer_count = 0;
  g_socket_test->timer = kmalloc(sizeof(*g_socket_test->timer), GFP_KERNEL);
  if (!g_socket_test->timer) {
    printk(KERN_ERR SOCKET_TEST "failed to allocate timer");

    kfree(g_socket);
    g_socket = NULL;
    kfree(g_socket_test);
    g_socket_test = NULL;

    return -ENOMEM;
  }

  rc = socket_init(g_socket, socket_test_consumer, NULL);
  if (rc < 0) {
    printk(KERN_ERR SOCKET_TEST "failed to initialize socket");

    kfree(g_socket);
    g_socket = NULL;
    kfree(g_socket_test->timer);
    kfree(g_socket_test);
    g_socket_test = NULL;

    return rc;
  }

  rc = socket_listen(g_socket);
  if (rc < 0) {
    printk(KERN_ERR SOCKET_TEST "failed to start socket");

    kfree(g_socket);
    g_socket = NULL;
    kfree(g_socket_test->timer);
    kfree(g_socket_test);
    g_socket_test = NULL;

    return rc;
  }

  timer_setup(g_socket_test->timer, socket_test_timer, 0);

  printk(KERN_INFO SOCKET_TEST "initialized");

  return 0;
}

void socket_test_exit(void) {
  int rc;

  printk(KERN_INFO SOCKET_TEST "exiting");
  if (g_socket != NULL) {
    rc = socket_close(g_socket);
    if (rc < 0) {
      printk(KERN_ERR SOCKET_TEST "failed to stop socket %d", rc);
    }

    kfree(g_socket);
    g_socket = NULL;
  }

  if (g_socket_test != NULL) {
    if (g_socket_test->timer != NULL) {
      del_timer(g_socket_test->timer);
      kfree(g_socket_test->timer);
      kfree(g_socket_test->wbuf);
    }

    kfree(g_socket_test);
    g_socket_test = NULL;
  }

  printk(KERN_INFO SOCKET_TEST "completed");
}

#define DRIVER_VERSION "v0.1"
#define DRIVER_AUTHOR "Stephan Zuercher <zuercher@gmail.com>"
#define DRIVER_DESC "Kernel Socket Test Module"

MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);

module_init(socket_test_init);
module_exit(socket_test_exit);
