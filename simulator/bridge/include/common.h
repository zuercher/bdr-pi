#ifndef _TTY_BRIDGE_COMMON_H_
#define _TTY_BRIDGE_COMMON_H_ 1

#define BRIDGE_DRIVER_NAME "fake_racecap_tty"
#define BRIDGE_TTY_NAME    "ttyUSB_FAKE_RACECAP"

#define BRIDGE_SOCKET_DESC     "bdr-pi-tty-bridge-socket"
#define BRIDGE_SOCKET_NAME     "\0" BRIDGE_SOCKET_DESC

// Length of BRIDGE_SOCKET_NAME (same as storage size of
// BRIDGE_SOCKET_DESC) which counts the null terminator.
#define BRIDGE_SOCKET_NAME_LEN (sizeof(BRIDGE_SOCKET_DESC))

#endif // _TTY_BRIDGE_COMMON_H_
