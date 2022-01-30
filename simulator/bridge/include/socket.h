#ifndef _TTY_BRIDGE_SOCKET_H_
#define _TTY_BRIDGE_SOCKET_H_ 1

struct bridge_socket {
  struct mutex mutex;
  struct socket* listener;
  struct socket* accepted;
  void* buf;
  int paused;
  int pending_data;

  int (*consume)(void* data, void* payload, int len);
  void *consumer_data;
};

// initial the bridge_socket and set the consumer callback
int socket_init(struct bridge_socket*, int (*)(void*, void*, int), void*);

// start listening
int socket_listen(struct bridge_socket*);

// start close the listener and free all resources
int socket_close(struct bridge_socket*);

// write the give data/length
int socket_write(struct bridge_socket*, void*, int);

// pause reading
void socket_pause(struct bridge_socket*);

// resume reading
void socket_resume(struct bridge_socket*);

#endif /* _TTY_BRIDGE_SOCKET_H_ */
