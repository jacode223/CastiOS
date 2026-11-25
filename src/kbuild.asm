; Build a candidate in the transactional NASM snapshot. No boot sectors touched.
cmd_kbuild:
    mov edi, LINE
    mov esi, kbuild_args
    call copy
    mov dword [args], LINE
    jmp cmd_nasm
kbuild_args db '-f bin src/kernel.asm -o kernel.img',0
