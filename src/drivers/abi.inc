; ABI v1: todos los campos son dword, direcciones lineales de 32 bits.
%define DRIVER_ABI 1
%define D_ABI 0
%define D_NAME 4
%define D_CLASS 8
%define D_PROBE 12
%define D_INIT 16
%define D_READ 20
%define D_WRITE 24
%define D_IOCTL 28
%define D_STATE 32
%define D_ERROR 36
%define D_SIZE 40
%define REGISTERED 0
%define READY 1
%define ABSENT 2
%define FAILED 3
%define OK 0
%define ENODEV 1
%define ENOSYS 2
%define EINVAL 3
%define EBUSY 4
%define ENOSPC 5
%define EIO 6
%define MAX_DRIVERS 16
; DRIVER descriptor, nombre, clase, probe, init, read, write, ioctl
%macro DRIVER 8
align 4
%1:
    dd DRIVER_ABI, %2, %3, %4, %5, %6, %7, %8, REGISTERED, OK
%endmacro
