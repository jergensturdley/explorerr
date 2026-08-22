#include "fork_shim.h"
#include <unistd.h>

pid_t fork_shim(void) {
    return fork();
}
