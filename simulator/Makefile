KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD)

clean:
	rm -f \
		thread_test_driver thread_test_driver.o \
		thread_test_server thread_test_server.o
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean

%.o : %.c
	$(CC) $(CFLAGS) $< -c

test: thread_test_driver thread_test_server

thread_test_driver: thread_test_driver.o
	$(CC) -o $@ $<

thread_test_driver.o: thread_test_driver.c

thread_test_server: thread_test_server.o
	$(CC) -o $@ $<

thread_test_server.o: thread_test_server.c
