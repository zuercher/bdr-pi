#ifndef _TTY_BRIDGE_THREAD_H_
#define _TTY_BRIDGE_THREAD_H_ 1

struct bridge_thread {
  struct mutex mutex;
  struct socket* listener;
  struct socket* accepted;
  void* buf;
  int paused;

  int (*consume)(void* data, void* payload, int len);
  void *consumer_data;
};

int thread_init(struct bridge_thread*, int (*)(void*, void*, int), void*);
int thread_start(struct bridge_thread*);
int thread_stop(struct bridge_thread*);
int thread_write(struct bridge_thread*, void*, int);
void thread_pause(struct bridge_thread*);
void thread_unpause(struct bridge_thread*);

#endif /* _TTY_BRIDGE_THREAD_H_ */
