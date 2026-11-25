; CastiOS i386 AX05: syscalls para obtener PID y ceder CPU.
%macro casti_getpid 0
    mov eax, 3
    int 0x80
%endmacro
%macro casti_yield 0
    mov eax, 2
    int 0x80
%endmacro
