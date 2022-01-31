#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/wait.h>
#include <linux/tty.h>
#include <linux/tty_driver.h>
#include <linux/tty_flip.h>
#include <linux/serial.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/version.h>

#include "common.h"
#include "socket.h"

#define DRIVER_VERSION "v0.1"
#define DRIVER_AUTHOR "Stephan Zuercher <zuercher@gmail.com>"
#define DRIVER_DESC "Fake Race Capture TTY driver"

MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);
MODULE_LICENSE("Dual MIT/GPL");

#if BRIDGE_DEBUG > 0
#undef pr_debug
#define pr_debug pr_info
#endif

#define BRIDGE_TTY_MAJOR          233   // seems free on this raspberry pi :-/
#define BRIDGE_TTY_MINORS         1     // just the 1 device

struct bridge_serial {
  struct tty_struct *tty;
  int open_count;
  struct mutex mutex;
  struct bridge_socket *socket;

  int msr;
  int mcr;

  struct serial_struct serial;
  wait_queue_head_t wait;
  struct async_icount icount;
};

static struct bridge_serial *bridge = NULL;
static struct tty_port bridge_tty_port = { 0 };
static struct bridge_socket bridge_socket = { 0 };

static int bridge_open(struct tty_struct *tty, struct file *file)
{
  tty->driver_data = NULL;

  pr_debug("fake racecap open\n");

  if (bridge == NULL) {
    // first open of this tty
    bridge = kmalloc(sizeof(*bridge), GFP_KERNEL);
    if (bridge == NULL) {
      pr_err("fake racecap open failed: no memory\n");
      return -ENOMEM;
    }

    memset(bridge, 0, sizeof(*bridge));
    mutex_init(&bridge->mutex);
  }

  mutex_lock(&bridge->mutex);

  // reference ourselves from the ttv and remember our tty
  tty->driver_data = bridge;
  bridge->tty = tty;

  bridge->open_count++;

  if (bridge->open_count == 1) {
    bridge->socket = &bridge_socket;
  }

  mutex_unlock(&bridge->mutex);

  return 0;
}

static void do_close(struct bridge_serial *bridge)
{
  mutex_lock(&bridge->mutex);

  if (!bridge->open_count) {
    // never opened?
    goto exit;
  }

  bridge->open_count--;

  if (bridge->open_count <= 0) {
    bridge->socket = NULL;
   }

exit:
  mutex_unlock(&bridge->mutex);
}

static void bridge_close(struct tty_struct *tty, struct file *file)
{
  struct bridge_serial *bridge = tty->driver_data;

  pr_debug("fake racecap close\n");

  if (bridge != NULL) {
    do_close(bridge);
  }
}

static int bridge_write(struct tty_struct *tty, const unsigned char *buffer, int count)
{
  struct bridge_serial *bridge = tty->driver_data;
  //  int i;
  int retval = -EINVAL;

  pr_debug("fake racecap write\n");

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);

  if (!bridge->open_count || bridge->socket == NULL) {
    // never opened?
    goto exit;
  }

  retval = socket_write(bridge->socket, (void*)buffer, count);
  if (retval < 0) {
    pr_err("socket write error %d\n", retval);
  } else if (retval < count) {
    pr_err("socket write underflow of %d bytes (wrote %d)\n", count - retval, retval);
  }

exit:
  mutex_unlock(&bridge->mutex);

  return retval;
}

#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 14, 0))
static int bridge_write_room(struct tty_struct *tty)
#else
static unsigned int bridge_write_room(struct tty_struct *tty)
#endif
{
  struct bridge_serial *bridge = tty->driver_data;
  int room = -EINVAL;

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);

  if (!bridge->open_count) {
    // never opened?
    goto exit;
  }

  // TODO: this should be less aspirational
  room = 4*1024;

exit:
  mutex_unlock(&bridge->mutex);
  return room;
}

static int bridge_read(void* ctxt, void* data, int len) {
  struct tty_struct *tty;
  struct tty_port *port;
  int rc = -EINVAL;

  pr_debug("fake racecap read\n");

  if (bridge == NULL) {
    return -ENODEV;
  }

  if (len == 0) {
    return 0;
  }

  mutex_lock(&bridge->mutex);

  if (!bridge->open_count || bridge->socket == NULL) {
    // never opened?
    goto exit;
  }

  tty = bridge->tty;
  port = tty->port;

  rc = tty_insert_flip_string_fixed_flag(port, (const unsigned char*)data, TTY_NORMAL, (size_t)len);
  if (rc < len) {
    pr_err("buffer underflow of %d bytes (wrote %d)\n", len - rc, rc);
  }
  tty_flip_buffer_push(port);

 exit:
  mutex_unlock(&bridge->mutex);

  return rc;
}

static void bridge_set_termios(struct tty_struct *tty, struct ktermios *old_termios)
{
  unsigned int cflag = tty->termios.c_cflag;
  unsigned int ocflag = 0;

  if (old_termios) {
    ocflag = old_termios->c_cflag;
    if (cflag == ocflag) {
      pr_debug("fake racecap set_termios -- no change %08x\n", cflag);
      return;
    }
  }

  pr_debug("fake racecap set_termios -- %08x to %08x\n", ocflag, cflag);
}

// Fake UART values
#define MCR_DTR  (1 << 0)
#define MCR_RTS  (1 << 1)
#define MCR_LOOP (1 << 2)
#define MSR_CTS  (1 << 3)
#define MSR_CD   (1 << 4)
#define MSR_RI   (1 << 5)
#define MSR_DSR  (1 << 6)

static int bridge_tiocmget(struct tty_struct *tty)
{
  struct bridge_serial *bridge = tty->driver_data;
  unsigned int result = 0;
  unsigned int msr;
  unsigned int mcr;

  mutex_lock(&bridge->mutex);

  msr = bridge->msr;
  mcr = bridge->mcr;

  result =
    ((mcr & MCR_DTR)  ? TIOCM_DTR  : 0) |  // DTR
    ((mcr & MCR_RTS)  ? TIOCM_RTS  : 0) |  // RTS
    ((mcr & MCR_LOOP) ? TIOCM_LOOP : 0) |  // LOOP
    ((msr & MSR_CTS)  ? TIOCM_CTS  : 0) |  // CTS
    ((msr & MSR_CD)   ? TIOCM_CAR  : 0) |  // carrier detect
    ((msr & MSR_RI)   ? TIOCM_RI   : 0) |  // ring
    ((msr & MSR_DSR)  ? TIOCM_DSR  : 0);   // DSR

  mutex_unlock(&bridge->mutex);

  pr_debug("fake racecap tiocmget %08x\n", result);

  return result;
}

static int bridge_tiocmset(struct tty_struct *tty,
                           unsigned int set,
                           unsigned int clear)
{
  struct bridge_serial *bridge = tty->driver_data;
  unsigned int mcr;

  pr_debug("fake racecap tiocmset set %08x\n, clear %08x", set, clear);

  mutex_lock(&bridge->mutex);

  mcr = bridge->mcr;
  if (set & TIOCM_RTS) {
    mcr |= MCR_RTS;
  }
  if (set & TIOCM_DTR) {
    mcr |= MCR_RTS;
  }

  if (clear & TIOCM_RTS) {
    mcr &= ~MCR_RTS;
  }
  if (clear & TIOCM_DTR) {
    mcr &= ~MCR_RTS;
  }

  bridge->mcr = mcr;

  mutex_unlock(&bridge->mutex);

  return 0;
}

static int bridge_proc_show(struct seq_file *m, void *v)
{
  seq_printf(m, "bridgeserinfo:1.0 driver:%s\n", DRIVER_VERSION);
  if (bridge != NULL) {
    seq_printf(m, "1\n");
  }

  return 0;
}

static int bridge_ioctl_tiocgserial(struct tty_struct *tty,
                                    unsigned int cmd,
                                    unsigned long arg)
{
  struct bridge_serial *bridge = tty->driver_data;

  if (cmd == TIOCGSERIAL) {
    struct serial_struct tmp;

    if (!arg) {
      return -EFAULT;
    }

    memset(&tmp, 0, sizeof(tmp));

    mutex_lock(&bridge->mutex);

    tmp.type = bridge->serial.type;
    tmp.line = bridge->serial.line;
    tmp.port = bridge->serial.port;
    tmp.irq = bridge->serial.irq;
    tmp.flags = ASYNC_SKIP_TEST | ASYNC_AUTO_IRQ;
    tmp.xmit_fifo_size = bridge->serial.xmit_fifo_size;
    tmp.baud_base = bridge->serial.baud_base;
    tmp.close_delay = 5*HZ;
    tmp.closing_wait = 30*HZ;
    tmp.custom_divisor = bridge->serial.custom_divisor;
    tmp.hub6 = bridge->serial.hub6;
    tmp.io_type = bridge->serial.io_type;

    mutex_unlock(&bridge->mutex);

    if (copy_to_user((void __user *)arg, &tmp, sizeof(struct serial_struct))) {
      return -EFAULT;
    }

    return 0;
  }

  return -ENOIOCTLCMD;
}

static int bridge_ioctl_tiocmiwait(struct tty_struct *tty,
                                   unsigned int cmd,
                                   unsigned long arg)
{
  struct bridge_serial *bridge = tty->driver_data;

  if (cmd == TIOCMIWAIT) {
    DECLARE_WAITQUEUE(wait, current);
    struct async_icount cnow;
    struct async_icount cprev;

    cprev = bridge->icount;
    while (1) {
      add_wait_queue(&bridge->wait, &wait);
      set_current_state(TASK_INTERRUPTIBLE);
      schedule();
      remove_wait_queue(&bridge->wait, &wait);

      if (signal_pending(current)) {
        return -ERESTARTSYS;
      }

      cnow = bridge->icount;
      if (cnow.rng == cprev.rng && cnow.dsr == cprev.dsr &&
          cnow.dcd == cprev.dcd && cnow.cts == cprev.cts) {
        // no change is an error
        return -EIO;
      }
      if (((arg & TIOCM_RNG) && (cnow.rng != cprev.rng)) ||
          ((arg & TIOCM_DSR) && (cnow.dsr != cprev.dsr)) ||
          ((arg & TIOCM_CD) && (cnow.dcd != cprev.dcd)) ||
          ((arg & TIOCM_CTS) && (cnow.cts != cprev.cts))) {
        return 0;
      }
      cprev = cnow;
    }
  }
  return -ENOIOCTLCMD;
}

static int bridge_ioctl_tiocgicount(struct tty_struct *tty,
                                    unsigned int cmd,
                                    unsigned long arg)
{
  struct bridge_serial *bridge = tty->driver_data;

  if (cmd == TIOCGICOUNT) {
    struct async_icount cnow = bridge->icount;
    struct serial_icounter_struct icount;

    icount.cts = cnow.cts;
    icount.dsr = cnow.dsr;
    icount.rng = cnow.rng;
    icount.dcd = cnow.dcd;
    icount.rx = cnow.rx;
    icount.tx = cnow.tx;
    icount.frame = cnow.frame;
    icount.overrun = cnow.overrun;
    icount.parity = cnow.parity;
    icount.brk = cnow.brk;
    icount.buf_overrun = cnow.buf_overrun;

    if (copy_to_user((void __user *)arg, &icount, sizeof(icount))) {
      return -EFAULT;
    }
    return 0;
  }
  return -ENOIOCTLCMD;
}

static int bridge_ioctl(struct tty_struct *tty,
                        unsigned int cmd,
                        unsigned long arg)
{
  switch (cmd) {
  case TIOCGSERIAL:
    return bridge_ioctl_tiocgserial(tty, cmd, arg);
  case TIOCMIWAIT:
    return bridge_ioctl_tiocmiwait(tty, cmd, arg);
  case TIOCGICOUNT:
    return bridge_ioctl_tiocgicount(tty, cmd, arg);
  }

  return -ENOIOCTLCMD;
}


static const struct tty_operations serial_ops = {
  .open = bridge_open,
  .close = bridge_close,
  .write = bridge_write,
  .write_room = bridge_write_room,
  .set_termios = bridge_set_termios,
  .proc_show = bridge_proc_show,
  .tiocmget = bridge_tiocmget,
  .tiocmset = bridge_tiocmset,
  .ioctl = bridge_ioctl,
};

static struct tty_driver *bridge_tty_driver;

static int __init bridge_init(void)
{
  struct device* dev;
  int retval;

  bridge_tty_driver = alloc_tty_driver(BRIDGE_TTY_MINORS);
  if (bridge_tty_driver == NULL) {
    pr_err("failed to alloc tty driver\n");
    return -ENOMEM;
  }

  bridge_tty_driver->owner = THIS_MODULE;
  bridge_tty_driver->driver_name = BRIDGE_DRIVER_NAME;
  bridge_tty_driver->name = BRIDGE_TTY_NAME;
  bridge_tty_driver->major = BRIDGE_TTY_MAJOR;
  bridge_tty_driver->type = TTY_DRIVER_TYPE_SERIAL;
  bridge_tty_driver->subtype = SERIAL_TYPE_NORMAL;
  bridge_tty_driver->flags = TTY_DRIVER_REAL_RAW | TTY_DRIVER_DYNAMIC_DEV;
  bridge_tty_driver->init_termios = tty_std_termios;
  bridge_tty_driver->init_termios.c_cflag = B9600 | CS8 | CREAD | HUPCL | CLOCAL;
  tty_set_operations(bridge_tty_driver, &serial_ops);

  tty_port_init(&bridge_tty_port);
  tty_port_link_device(&bridge_tty_port, bridge_tty_driver, 0);

  retval = tty_register_driver(bridge_tty_driver);
  if (retval) {
    pr_err("failed to register %s %d\n", BRIDGE_DRIVER_NAME, retval);
    put_tty_driver(bridge_tty_driver);
    return retval;
  }

  dev = tty_register_device(bridge_tty_driver, 0, NULL);
  if (IS_ERR(dev)) {
    pr_err("failed to register device for %s minor %d %ld\n", BRIDGE_DRIVER_NAME, 0, PTR_ERR(dev));
    tty_unregister_driver(bridge_tty_driver);
    put_tty_driver(bridge_tty_driver);
    return PTR_ERR(dev);
  }

  retval = socket_init(&bridge_socket, bridge_read, NULL);
  if (!retval) {
    retval = socket_listen(&bridge_socket);
  }
  if (retval < 0) {
    pr_err("failed to init socket for %s minor %d %d\n", BRIDGE_DRIVER_NAME, 0, retval);
    tty_unregister_device(bridge_tty_driver, 0);
    tty_unregister_driver(bridge_tty_driver);
    put_tty_driver(bridge_tty_driver);
    return retval;
  }

  pr_info(DRIVER_DESC " " DRIVER_VERSION "\n");

  return retval;
}

static void __exit bridge_exit(void)
{
  struct bridge_serial *b = bridge;

  bridge = NULL;
  if (b != NULL) {
    while (b->open_count > 0) {
      do_close(b);
    }
  }

  socket_close(&bridge_socket);

  tty_unregister_device(bridge_tty_driver, 0);
  tty_unregister_driver(bridge_tty_driver);
  put_tty_driver(bridge_tty_driver);

  pr_info(DRIVER_DESC " " DRIVER_VERSION " exit\n");
}

module_init(bridge_init);
module_exit(bridge_exit);
