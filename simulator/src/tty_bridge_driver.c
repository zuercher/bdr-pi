#include <linux/config.h>
#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/tty.h>
#include <linux/tty_driver.h>
#include <linux/tty_flip.h>
#include <linux/module.h>
#include <linux/sched.h>
#include "tty_bridge_driver.h"

#define DRIVER_VERSION "v0.1"
#define DRIVER_AUTHOR "Stephan Zuercher <zuercher@gmail.com>"
#define DRIVER_DESC "Socket bridge TTY driver"

MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);
MODULE_LICENSE("Apache-2.0");

#define BRIDGE_TTY_MAJOR  240     /* experimental range */
#define BRIDGE_TTY_MINORS 255     /* use the whole major up */

#define BRIDGE "bridge: "

static struct tty_struct* bridge_tty[BRIDGE_TTY_MINORS];
static struct termios* bridge_termios[BRIDGE_TTY_MINORS];
static struct termios* bridge_termios_locked[BRIDGE_TTY_MINORS];

// Driver

struct bridge_serial {
  struct tty_struct* tty;
  int open_count;
  struct mutex mutex;
  struct bridge_thread thread;
};

static int bridge_refcount;

static struct tty_driver bridge_tty_driver;
static struct tty_struct* bridge_tty[BRIDGE_TTY_MINORS];
static struct termios* bridge_termios[BRIDGE_TTY_MINORS];
static struct termios* bridge_termios_locked[BRIDGE_TTY_MINORS];
static struct bridge_serial* bridge_table[BRIDGE_TTY_MINORS];

static int bridge_read(struct bridge_serial* bridge, void* data, int len)
{
  // TODO
}

static int bridge_open(struct tty_struct* tty, struct file *filep)
{
  struct bridge_serial* bridge;
  int rc = 0;

  MOD_INC_USE_COUNT;

  tty->driver_data = NULL;

  bridge = bridge_table[minor(tty->device)];
  if (bridge == NULL) {
    bridge = kmalloc(sizeof(*bridge), GFP_KERNEL);
    if (bridge == NULL) {
      MOD_DEC_USE_COUNT;
      return -ENONMEM;
    }

    rc = thread_init(&bridge->therad);
    if (rc < 0) {
      printk(KERN_ERR BRIDGE "failed to init thread");
      return rc;
    }

    bridge->open_count = 0;
    mutex_init(&bridge->mutex);
  }

  mutex_lock(&bridge->mutex);

  tty->driver_data = bridge;
  bridge->tty = tty;

  bridge->open_count++;
  if (bridge->open_count == 1) {
    rc = thread_start(&bridge->thread);
    if (rc < 0) {
      printk(KERN_ERR BRIDGE "failed to start thread");
      goto exit;
    }
  }

 exit:
  mutex_unlock(&bridge->mutex);

  return rc;
}

static void close_impl(struct bridge_serial* bridge) {
  mutex_lock(&bridge->mutex);

  if (bridge->open_count == 0) {
    return;
  }

  bridge->open_count--;
  if (bridge->open_count <= 0) {
    int rc = thread_stop(t);
    if (rc < 0) {
      printk(KERN_ERR BRIDGE "failed to stop thread: %d", rc);
    }
  }

  MOD_DEC_USE_COUNT;

  mutex_unlock(&bridge->mutex);
}

static void bridge_close(struct tty_struct* tty, struct file* filep) {
  struct bridge_serial* bridge = (struct bridge_serial*)tty->driver_data;
  if (bridge == NULL) {
    return;
  }
  close_impl(bridge);
}

static int bridge_write(struct tty_struct* tty, int user, const unsigned char* buf, int count)
{
  struct bridge_serial* bridge = (struct bridge_serial*)tty->driver_data;

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);

  if (bridge->open_count == 0) {
    // not open?!
    mutex_unlock(&bridge->mutex);
    return -EINVAL;
  }

  // TODO: write to socket and return the number of bytes written

  mutex_unlock(&bridge->mutex);

  return count;
}

static int bridge_write_room(struct tty_struct* tty)
{
  struct bridge_serial* bridge = (struct bridge_serial*)tty->driver_data;

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);

  if (!bridge->open_count) {
    // not open?!
    mutex_unlock(&bridge->mutex);
    return -EINVAL;
  }

  room = 4*1024; // something like that

  mutex_unlock(&bridge->mutex);

  return room;
}

int bridge_ioctl(struct tty_struct* tty, unsigned int cmd, unsigned long arg)
{
  // Yes, sure, we definitely support that.
  return 0;
}

void bridge_throttle(struct tty_struct* tty)
{
  struct bridge_serial* bridge = (struct bridge_serial*)tty->driver_data;

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);
  thread_pause(&bridge->thread);
  mutex_unlock(&bridge->mutex);
}

void bridge_unthrottle(struct tty_struct* tty)
{
  struct bridge_serial* bridge = (struct bridge_serial*)tty->driver_data;

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);
  thread_unpause(&bridge->thread);
  mutex_unlock(&bridge->mutex);
}

static struct tty_driver bridge_tty_driver = {
 magic:          TTY_DRIVER_MAGIC,
 driver_name:    "bridge_tty",
#ifdef CONFIG_DEVFS_FS
 name:           "tts/btty%d",
#else
 name:           "btty",
#endif
 major:          BRIDGE_TTY_MAJOR,
 num:            BRIDGE_TTY_MINORS,
 type:           TTY_DRIVER_TYPE_SERIAL,
 subtype:        SERIAL_TYPE_NORMAL,
 flags:          TTY_DRIVER_REAL_RAW | TTY_DRIVER_NO_DEVFS,

 refcount:       &bridge_refcount,
 table:          bridge_tty,
 termios:        bridge_termios,
 termios_locked: bridge_termios_locked,

 open:           bridge_open,
 close:          bridge_close,
 write:          bridge_write,
 write_room:     bridge_write_room,
 ioctl:          bridge_ioctl,
 throttle:       bridge_throttle,
 unthrottle:     bridge_unthrottle,
};

static int __init bridge_init(void)
{
  bridge_tty_driver.init_termios = tty_std_termios;
  bridge_tty_driver.init_termios.c_cflag = B9600 | CS8 | CREAD | HUPCL | CLOCAL;
  if (tty_register_driver(&bridge_tty_driver)) {
    printk(KERN_ERR BRIDGE "failed to register bridge tty driver");
    return -1;
  }
  return 0;
}

static void __exit bridge_exit(void)
{
  tty_unregister_driver(&bridge_tty_driver);
}

module_init (bridge_init);
module_exit (bridge_exit);
