KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD)

clean:
	rm -f \
		socket_test_driver test/*.o \
		socket_test_server test/*.o
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean

%.o : %.c
	$(CC) $(CFLAGS) $< -c

test: socket_test_driver socket_test_server

socket_test_driver: test/socket_test_driver.c
	$(CC) -I include -o $@ $<

socket_test_server: test/socket_test_server.c
	$(CC) -I include -o $@ $<
