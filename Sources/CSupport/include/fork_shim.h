#ifndef FORK_SHIM_H
#define FORK_SHIM_H

#include <sys/types.h>

// Swift marks fork() unavailable; expose it through a C shim so the pty can spawn a shell.
pid_t fork_shim(void);

#endif
