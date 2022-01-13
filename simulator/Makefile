ifneq ($(KERNELRELEASE),)

#
# When invoked from KERNDELDIR's make modules:
#
obj-m += thread_test.o
#obj-m += tty_bridge_driver.o

thread_test-objs := thread_test.o thread.o

#tty_bridge_driver-objs := tty_bridge_driver.o thread.o

else

#
# When invoked from the local directory.
#

KERNELDIR ?= /lib/modules/$(shell uname -r)/build

PWD := $(shell pwd)

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

%.o : %.c
	$(CC) $(CFLAGS) $< -c

test: thread_test_driver

thread_test_driver: thread_test_driver.o
	$(CC) -o $@ $<

thread_test_driver.o: thread_test_driver.c

endif
