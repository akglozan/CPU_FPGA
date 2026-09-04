//
// soc_syscalls.c -- minimal newlib syscall stubs for bare-metal CPU_FPGA.
//
// This build links newlib-nano (rv32im/ilp32 multilib) for string.h
// (memcpy/memset/strlen/...) and a compact printf/sprintf family --
// deliberately NOT for a real filesystem or process model. Every
// syscall newlib might still reach for gets a stub: _write goes to the
// UART (so printf/I_Error output is visible over serial, matching
// "uart_print_str-style output" from the Phase 5.2 roadmap item), and
// everything else either fails harmlessly or halts, since there's no
// OS underneath to actually service it.
//
// _sbrk feeds a small fixed region (see linker_sdram.ld's
// _mischeap_start/_mischeap_end) reserved specifically for this --
// it is NOT the same memory as Doom's own Z_Malloc zone (that gets
// its own much larger region directly from I_ZoneBase() in
// i_system.c). This heap exists only for whatever small incidental
// allocations newlib itself wants (if any) plus the handful of
// leftover libc malloc() call sites patched in m_config.c/m_argv.c
// etc that aren't worth routing through Z_Malloc.
//

#include <sys/stat.h>
#include <errno.h>
#include <stdint.h>

extern uint8_t _mischeap_start[];
extern uint8_t _mischeap_end[];

void uart_putc(uint8_t c);

static uint8_t *heap_ptr = 0;

void *_sbrk(int incr)
{
    uint8_t *prev;

    if (heap_ptr == 0) {
        heap_ptr = _mischeap_start;
    }

    prev = heap_ptr;

    if (heap_ptr + incr > _mischeap_end || heap_ptr + incr < _mischeap_start) {
        errno = ENOMEM;
        return (void *)-1;
    }

    heap_ptr += incr;
    return prev;
}

int _write(int fd, const char *buf, int len)
{
    int i;
    (void)fd;

    for (i = 0; i < len; i++) {
        if (buf[i] == '\n') {
            uart_putc('\r');
        }
        uart_putc((uint8_t)buf[i]);
    }

    return len;
}

int _read(int fd, char *buf, int len)
{
    (void)fd;
    (void)buf;
    (void)len;
    return 0; // no stdin
}

int _close(int fd)
{
    (void)fd;
    return -1;
}

int _fstat(int fd, struct stat *st)
{
    (void)fd;
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd)
{
    (void)fd;
    return 1;
}

int _lseek(int fd, int ptr, int dir)
{
    (void)fd;
    (void)ptr;
    (void)dir;
    return 0;
}

int _kill(int pid, int sig)
{
    (void)pid;
    (void)sig;
    errno = EINVAL;
    return -1;
}

int _getpid(void)
{
    return 1;
}

void _exit(int status)
{
    (void)status;
    uart_putc('\r');
    uart_putc('\n');
    for (;;) {
        // nothing to return to -- halt
    }
}
