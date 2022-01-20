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

#include "socket.h"

#define DRIVER_VERSION "v0.1"
#define DRIVER_AUTHOR "Stephan Zuercher <zuercher@gmail.com>"
#define DRIVER_DESC "Socket bridge TTY driver"

MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);
MODULE_LICENSE("Dual MIT/GPL");

#ifdef BRIDGE_DEBUG
#define pr_debug pr_info
#endif

#define BRIDGE_TTY_MAJOR          233   // seems free on this raspberry pi :-/
#define BRIDGE_TTY_MINORS         1     // just the 1 device

struct bridge_serial {
  struct tty_struct *tty;
  int open_count;
  struct mutex mutex;
  struct timer_list timer;

  int msr;
  int mcr;

  struct serial_struct serial;
  wait_queue_head_t wait;
  struct async_icount icount;
};

static struct bridge_serial *bridge_table[BRIDGE_TTY_MINORS];
static struct tty_port bridge_tty_port[BRIDGE_TTY_MINORS];

static int bridge_open(struct tty_struct *tty, struct file *file)
{
  struct bridge_serial *bridge;
  int index;

  tty->driver_data = NULL;

  index = tty->index;
  bridge = bridge_table[index];
  if (bridge == NULL) {
    // first open of this tty
    bridge = kmalloc(sizeof(*bridge), GFP_KERNEL);
    if (bridge == NULL) {
      return -ENOMEM;
    }

    mutex_init(&bridge->mutex);
    bridge->open_count = 0;

    bridge_table[index] = bridge;
  }

  mutex_lock(&bridge->mutex);

  // reference ourselves from the ttv and remember our tty
  tty->driver_data = bridge;
  bridge->tty = tty;

  bridge->open_count++;

  if (bridge->open_count == 1) {
    // TODO first open: assign socket
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
    // TODO: last close: unassign socket

   }
exit:
  mutex_unlock(&bridge->mutex);
}

static void bridge_close(struct tty_struct *tty, struct file *file)
{
  struct bridge_serial *bridge = tty->driver_data;

  if (bridge != NULL) {
    do_close(bridge);
  }
}

static int bridge_write(struct tty_struct *tty, const unsigned char *buffer, int count)
{
  struct bridge_serial *bridge = tty->driver_data;
  //  int i;
  int retval = -EINVAL;

  if (bridge == NULL) {
    return -ENODEV;
  }

  mutex_lock(&bridge->mutex);

  if (!bridge->open_count) {
    // never opened?
    goto exit;
  }

  // TODO: write to socket
  retval = count;

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

  // how much?
  room = 4*1024;

exit:
  mutex_unlock(&bridge->mutex);
  return room;
}

#define RELEVANT_IFLAG(iflag) ((iflag) & (IGNBRK|BRKINT|IGNPAR|PARMRK|INPCK))

static void bridge_set_termios(struct tty_struct *tty, struct ktermios *old_termios)
{
  unsigned int cflag = tty->termios.c_cflag;

  pr_debug("bridge_set_termios\n");

  // Is something changing?
  if (old_termios) {
    if ((cflag == old_termios->c_cflag) &&
        (RELEVANT_IFLAG(tty->termios.c_iflag) ==
         RELEVANT_IFLAG(old_termios->c_iflag))) {
      return;
    }
  }

  // report byte size
  switch (cflag & CSIZE) {
  case CS5:
    pr_debug(" - data bits = 5\n");
    break;
  case CS6:
    pr_debug(" - data bits = 6\n");
    break;
  case CS7:
    pr_debug(" - data bits = 7\n");
    break;
  default:
  case CS8:
    pr_debug(" - data bits = 8\n");
    break;
  }

  // report parity
  if (cflag & PARENB) {
    if (cflag & PARODD) {
      pr_debug(" - parity = odd\n");
    } else {
      pr_debug(" - parity = even\n");
    }
  } else {
    pr_debug(" - parity = none\n");
  }

  // report stop bits
  if (cflag & CSTOPB) {
    pr_debug(" - stop bits = 2\n");
  } else {
    pr_debug(" - stop bits = 1\n");
  }

  // report h/w flow control
  if (cflag & CRTSCTS) {
    pr_debug(" - RTS/CTS is enabled\n");
  } else {
    pr_debug(" - RTS/CTS is disabled\n");
  }

  // report s/w flow control
  if (I_IXOFF(tty) || I_IXON(tty)) {
    unsigned char stop_char  = STOP_CHAR(tty);
    unsigned char start_char = START_CHAR(tty);

    /* if we are implementing INBOUND XON/XOFF */
    if (I_IXOFF(tty)) {
      pr_debug(" - INBOUND XON/XOFF is enabled, "
        "XON = %2x, XOFF = %2x", start_char, stop_char);
    } else {
      pr_debug(" - INBOUND XON/XOFF is disabled");
    }

    /* if we are implementing OUTBOUND XON/XOFF */
    if (I_IXON(tty)) {
      pr_debug(" - OUTBOUND XON/XOFF is enabled, "
        "XON = %2x, XOFF = %2x", start_char, stop_char);
    } else {
      pr_debug(" - OUTBOUND XON/XOFF is disabled");
    }
  }

  // report the baud rate
  pr_debug(" - baud rate = %d", tty_get_baud_rate(tty));
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
  unsigned int msr = bridge->msr;
  unsigned int mcr = bridge->mcr;

  result = ((mcr & MCR_DTR)  ? TIOCM_DTR  : 0) |  /* DTR is set */
    ((mcr & MCR_RTS)  ? TIOCM_RTS  : 0) |  /* RTS is set */
    ((mcr & MCR_LOOP) ? TIOCM_LOOP : 0) |  /* LOOP is set */
    ((msr & MSR_CTS)  ? TIOCM_CTS  : 0) |  /* CTS is set */
    ((msr & MSR_CD)   ? TIOCM_CAR  : 0) |  /* Carrier detect is set*/
    ((msr & MSR_RI)   ? TIOCM_RI   : 0) |  /* Ring Indicator is set */
    ((msr & MSR_DSR)  ? TIOCM_DSR  : 0);  /* DSR is set */

  return result;
}

static int bridge_tiocmset(struct tty_struct *tty,
                           unsigned int set,
                           unsigned int clear)
{
  struct bridge_serial *bridge = tty->driver_data;
  unsigned int mcr = bridge->mcr;

  if (set & TIOCM_RTS)
    mcr |= MCR_RTS;
  if (set & TIOCM_DTR)
    mcr |= MCR_RTS;

  if (clear & TIOCM_RTS)
    mcr &= ~MCR_RTS;
  if (clear & TIOCM_DTR)
    mcr &= ~MCR_RTS;

  /* set the new MCR value in the device */
  bridge->mcr = mcr;
  return 0;
}

static int bridge_proc_show(struct seq_file *m, void *v)
{
  struct bridge_serial *bridge;
  int i;

  seq_printf(m, "bridgeserinfo:1.0 driver:%s\n", DRIVER_VERSION);
  for (i = 0; i < BRIDGE_TTY_MINORS; ++i) {
    bridge = bridge_table[i];
    if (bridge == NULL) {
      continue;
    }

    seq_printf(m, "%d\n", i);
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
  int retval;
  int i;

  bridge_tty_driver = alloc_tty_driver(BRIDGE_TTY_MINORS);
  if (bridge_tty_driver == NULL) {
    return -ENOMEM;
  }

  bridge_tty_driver->owner = THIS_MODULE;
  bridge_tty_driver->driver_name = "fake_racecap_tty";
  bridge_tty_driver->name = "ttyUSB_FAKE_RACECAP";
  bridge_tty_driver->major = BRIDGE_TTY_MAJOR,
  bridge_tty_driver->type = TTY_DRIVER_TYPE_SERIAL,
  bridge_tty_driver->subtype = SERIAL_TYPE_NORMAL,
  bridge_tty_driver->flags = TTY_DRIVER_REAL_RAW | TTY_DRIVER_DYNAMIC_DEV,
  bridge_tty_driver->init_termios = tty_std_termios;
  bridge_tty_driver->init_termios.c_cflag = B9600 | CS8 | CREAD | HUPCL | CLOCAL;
  tty_set_operations(bridge_tty_driver, &serial_ops);

  for (i = 0; i < BRIDGE_TTY_MINORS; i++) {
    tty_port_init(bridge_tty_port + i);
    tty_port_link_device(bridge_tty_port + i, bridge_tty_driver, i);
  }

  retval = tty_register_driver(bridge_tty_driver);
  if (retval) {
    pr_err("failed to register bridge tty driver %d", retval);
    put_tty_driver(bridge_tty_driver);
    return retval;
  }

  for (i = 0; i < BRIDGE_TTY_MINORS; ++i) {
    tty_register_device(bridge_tty_driver, i, NULL);
  }

  // TODO: init socket

  pr_info(DRIVER_DESC " " DRIVER_VERSION);
  return retval;
}

static void __exit bridge_exit(void)
{
  struct bridge_serial *bridge;
  int i;

  for (i = 0; i < BRIDGE_TTY_MINORS; ++i) {
    bridge = bridge_table[i];
    if (bridge) {
      while (bridge->open_count > 0) {
        do_close(bridge);
      }
    }
  }

  // TODO: close socket

  for (i = 0; i < BRIDGE_TTY_MINORS; ++i) {
    tty_unregister_device(bridge_tty_driver, i);
  }

  tty_unregister_driver(bridge_tty_driver);

  put_tty_driver(bridge_tty_driver);
}

module_init(bridge_init);
module_exit(bridge_exit);
