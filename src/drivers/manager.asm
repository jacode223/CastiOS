; Registro acotado de drivers integrados. Ningun puntero externo se ejecuta.
drivers_boot:
    mov esi, driver_manifest
.loop:
    lodsd
    test eax, eax
    jz .done
    mov ebx, eax
    push esi
    call driver_register
    test eax, eax
    jnz .error
    call driver_start
.error:
    pop esi
    jmp .loop
.done:
    ret

; EBX=descriptor estatico. EAX=status. Rechaza ABI, duplicados y exceso.
driver_register:
    pushad
    mov eax, EINVAL
    test ebx, ebx
    jz .done
    cmp dword [ebx+D_ABI], DRIVER_ABI
    jne .done
    mov esi, [ebx+D_NAME]
    test esi, esi
    jz .done
    cmp byte [esi], 0
    je .done
    push esi
    call length
    pop esi
    cmp eax, 15
    ja .bad_name
    mov eax, EINVAL
    cmp dword [ebx+D_CLASS], 0
    je .done
    call driver_find
    test eax, eax
    jz .duplicate
    mov ecx, [driver_count]
    mov eax, ENOSPC
    cmp ecx, MAX_DRIVERS
    jae .done
    mov [driver_registry+ecx*4], ebx
    inc dword [driver_count]
    mov dword [ebx+D_STATE], REGISTERED
    mov dword [ebx+D_ERROR], OK
    xor eax, eax
    jmp .done
.bad_name:
    mov eax, EINVAL
    jmp .done
.duplicate:
    mov eax, EBUSY
.done:
    mov [esp+28], eax
    popad
    ret

; ESI=nombre, EAX=status, EDX=descriptor; EBX preservado.
driver_find:
    push ebx
    push ecx
    push edi
    xor ecx, ecx
.loop:
    cmp ecx, [driver_count]
    jae .missing
    mov ebx, [driver_registry+ecx*4]
    mov edi, [ebx+D_NAME]
    call equal
    je .found
    inc ecx
    jmp .loop
.found:
    mov edx, ebx
    xor eax, eax
    jmp .done
.missing:
    xor edx, edx
    mov eax, ENODEV
.done:
    pop edi
    pop ecx
    pop ebx
    ret

; EBX debe pertenecer al registro. EAX=status.
driver_validate:
    push ecx
    xor ecx, ecx
.loop:
    cmp ecx, [driver_count]
    jae .bad
    cmp ebx, [driver_registry+ecx*4]
    je .ok
    inc ecx
    jmp .loop
.bad:
    mov eax, ENODEV
    pop ecx
    ret
.ok:
    xor eax, eax
    pop ecx
    ret

driver_start:
    call driver_validate
    test eax, eax
    jnz .return
    mov eax, EBUSY
    cmp dword [ebx+D_STATE], REGISTERED
    jne .return
    mov eax, [ebx+D_PROBE]
    call driver_optional
    test eax, eax
    jz .init
    cmp eax, ENODEV
    jne .failed
    mov dword [ebx+D_STATE], ABSENT
    push eax
    call driver_release_irqs
    pop eax
    jmp .save
.init:
    mov eax, [ebx+D_INIT]
    call driver_optional
    test eax, eax
    jnz .failed
    mov dword [ebx+D_STATE], READY
    jmp .save
.failed:
    mov dword [ebx+D_STATE], FAILED
    push eax
    call driver_release_irqs
    pop eax
.save:
    mov [ebx+D_ERROR], eax
.return:
    ret

driver_optional:
    test eax, eax
    jnz driver_callback
    ret
driver_callback:
    pushfd
    push ebx
    push esi
    push edi
    push ebp
    call eax
    cld
    pop ebp
    pop edi
    pop esi
    pop ebx
    popfd
    ret

; Read/write: EBX=descriptor, EDI=buffer, ECX=bytes; EAX=status, EDX=bytes.
; Ioctl: EBX=descriptor, EDX=opcode, EDI=buffer, ECX=capacidad.
driver_read:
    mov eax, D_READ
    jmp driver_invoke
driver_write:
    mov eax, D_WRITE
    jmp driver_invoke
driver_ioctl:
    mov eax, D_IOCTL
driver_invoke:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    call driver_validate
    test eax, eax
    jnz .invalid
    cmp dword [ebx+D_ABI], DRIVER_ABI
    jne .bad_abi
    cmp dword [ebx+D_STATE], READY
    jne .unavailable
    mov eax, [ebp-4]
    mov eax, [ebx+eax]
    test eax, eax
    jz .unsupported
    call driver_callback
    test eax, eax
    jnz .save
    cmp dword [ebp-4], D_IOCTL
    je .save
    cmp edx, [ebp-8]
    jbe .save
    mov eax, EIO
    jmp .save
.done:
    mov esp, ebp
    pop ebp
    ret
.invalid:
    mov eax, ENODEV
    xor edx, edx
    jmp .done
.bad_abi:
    mov eax, EINVAL
    jmp .save
.unavailable:
    mov eax, ENODEV
    jmp .save
.unsupported:
    mov eax, ENOSYS
.save:
    mov [ebx+D_ERROR], eax
    test eax, eax
    jz .done
    xor edx, edx
    jmp .done

; IRQ exclusivos: EAX=linea 0..15, ECX=callback, EBX=driver registrado.
; El handler recibe EAX=linea, EBX=propietario; no envia EOI.
irq_register:
    pushfd
    cli
    pushad
    mov edi, eax
    call driver_validate
    test eax, eax
    jnz .done
    mov eax, EINVAL
    cmp dword [ebx+D_STATE], READY
    ja .done
    cmp edi, 15
    ja .done
    cmp edi, 2
    je .done
    test ecx, ecx
    jz .done
    mov eax, EBUSY
    cmp dword [irq_callbacks+edi*4], 0
    jne .done
    mov [irq_callbacks+edi*4], ecx
    mov [irq_owners+edi*4], ebx
    mov ecx, edi
    mov dx, 0x21
    cmp ecx, 8
    jb .unmask
    ; Habilitar cascada IRQ2 y linea del PIC esclavo.
    in al, dx
    and al, 0xfb
    out dx, al
    mov dx, 0xa1
    sub ecx, 8
.unmask:
    mov ah, 1
    shl ah, cl
    not ah
    in al, dx
    and al, ah
    out dx, al
    xor eax, eax
.done:
    mov [esp+28], eax
    popad
    popfd
    ret

irq_unregister:
    pushfd
    cli
    pushad
    mov edi, eax
    mov eax, EINVAL
    cmp edi, 15
    ja .done
    cmp edi, 2
    je .done
    mov eax, ENODEV
    cmp dword [irq_callbacks+edi*4], 0
    je .done
    cmp ebx, [irq_owners+edi*4]
    jne .done
    mov ecx, edi
    mov dx, 0x21
    cmp ecx, 8
    jb .mask
    sub ecx, 8
    mov dx, 0xa1
.mask:
    mov ah, 1
    shl ah, cl
    in al, dx
    or al, ah
    out dx, al
    mov dword [irq_callbacks+edi*4], 0
    mov dword [irq_owners+edi*4], 0
    mov ecx, 8
.slaves:
    cmp dword [irq_callbacks+ecx*4], 0
    jne .success
    inc ecx
    cmp ecx, 16
    jb .slaves
    in al, 0x21
    or al, 4
    out 0x21, al
.success:
    xor eax, eax
.done:
    mov [esp+28], eax
    popad
    popfd
    ret
driver_release_irqs:
    pushad
    xor ebp, ebp
.loop:
    cmp ebx, [irq_owners+ebp*4]
    jne .next
    mov eax, ebp
    call irq_unregister
.next:
    inc ebp
    cmp ebp, 16
    jb .loop
    popad
    ret

%assign irq 0
%rep 16
irq_stub_%+irq:
    push dword irq
    jmp irq_common
%assign irq irq+1
%endrep
irq_common:
    pushad
    cld
    mov eax, [esp+32]
    ; IRQ7/15 espurias: comprobar el registro ISR del PIC.
    cmp eax, 7
    je .spurious_master
    cmp eax, 15
    jne .dispatch
    mov al, 0x0b
    out 0xa0, al
    in al, 0xa0
    test al, 0x80
    jz .master_eoi
    mov eax, 15
    jmp .dispatch
.spurious_master:
    mov al, 0x0b
    out 0x20, al
    in al, 0x20
    test al, 0x80
    jz .done
    mov eax, 7
.dispatch:
    mov ebx, [irq_owners+eax*4]
    mov edx, [irq_callbacks+eax*4]
    test edx, edx
    jz .eoi
    call edx
.eoi:
    cmp dword [esp+32], 8
    jb .master_eoi
    mov al, 0x20
    out 0xa0, al
.master_eoi:
    mov al, 0x20
    out 0x20, al
.done:
    call mt_schedule
    mov esp, eax
    popad
    add esp, 4
    iretd
irq_stubs:
%assign irq 0
%rep 16
    dd irq_stub_%+irq
%assign irq irq+1
%endrep

cmd_drivers:
    mov ebp, 0
.loop:
    cmp ebp, [driver_count]
    jae .done
    mov ebx, [driver_registry+ebp*4]
    call driver_print
    inc ebp
    jmp .loop
.done:
    ret
driver_print:
    mov esi, [ebx+D_NAME]
    call puts
    mov al, ' '
    call putc
    mov eax, [ebx+D_STATE]
    mov esi, [driver_states+eax*4]
    call puts
    mov al, ' '
    call putc
    mov esi, [ebx+D_CLASS]
    call puts
    call nl
    ret
cmd_drvinfo:
    mov esi, [args]
    call driver_find
    test eax, eax
    jnz driver_error
    mov ebx, edx
    call driver_print
    mov esi, driver_abi_msg
    call puts
    mov eax, [ebx+D_ABI]
    call number
    mov esi, driver_error_msg
    call puts
    mov eax, [ebx+D_ERROR]
    call number
    call nl
    mov esi, ops_msg
    call puts
    cmp dword [ebx+D_READ], 0
    je .write
    mov esi, read_msg
    call puts
.write:
    cmp dword [ebx+D_WRITE], 0
    je .ioctl
    mov esi, write_msg
    call puts
.ioctl:
    cmp dword [ebx+D_IOCTL], 0
    je .done
    mov esi, ioctl_msg
    call puts
.done:
    jmp nl
cmd_drvread:
    mov esi, [args]
    call driver_find
    test eax, eax
    jnz driver_error
    mov ebx, edx
    mov esi, [ebx+D_CLASS]
    mov edi, text_class
    call equal
    jne .invalid
    mov edi, driver_buffer
    mov ecx, 250
    call driver_read
    test eax, eax
    jnz driver_error
    cmp edx, 250
    ja .invalid
    mov byte [driver_buffer+edx], 0
    mov esi, driver_buffer
    call puts
    jmp nl
.invalid:
    mov eax, EIO
    jmp driver_error
cmd_drvwrite:
    mov esi, [args]
    mov edi, esi
.split:
    cmp byte [esi], 0
    je .empty
    cmp byte [esi], ' '
    je .cut
    inc esi
    jmp .split
.cut:
    mov byte [esi], 0
    inc esi
    call spaces
.empty:
    push esi
    mov esi, edi
    call driver_find
    pop edi
    test eax, eax
    jnz driver_error
    mov ebx, edx
    push edi
    mov esi, [ebx+D_CLASS]
    mov edi, text_class
    call equal
    pop edi
    jne .invalid
    mov esi, edi
    call length
    mov ecx, eax
    call driver_write
    test eax, eax
    jnz driver_error
    mov eax, edx
    call number
    mov esi, bytes_msg
    jmp puts
.invalid:
    mov eax, EINVAL
    jmp driver_error
driver_error:
    push eax
    mov esi, driver_error_msg
    call puts
    pop eax
    call number
    jmp nl

; Prueba del contrato sobre loopback; nunca escribe discos.
cmd_drvtest:
    mov ebx, bad_abi_descriptor
    call driver_register
    cmp eax, EINVAL
    jne .fail
    mov ebx, loopback_driver
    call driver_register
    cmp eax, EBUSY
    jne .fail
    mov ebx, 0
    call driver_read
    cmp eax, ENODEV
    jne .fail
    mov ebx, pit_driver
    xor eax, eax
    mov ecx, timer_tick
    call irq_register
    cmp eax, EBUSY
    jne .fail
    mov eax, 16
    call irq_register
    cmp eax, EINVAL
    jne .fail
    mov ebx, loopback_driver
    mov edi, driver_buffer
    mov ecx, 4
    mov edx, 1
    call driver_ioctl
    test eax, eax
    jnz .fail
    cmp edx, 4
    jne .fail
    xor edx, edx
    call driver_ioctl
    test eax, eax
    jnz .fail
    mov edx, 99
    call driver_ioctl
    cmp eax, EINVAL
    jne .fail
    mov ecx, 251
    call driver_write
    cmp eax, EINVAL
    jne .fail
    mov ebx, vga_driver
    call driver_read
    cmp eax, ENOSYS
    jne .fail
    call driver_regression_tests
    test eax, eax
    jnz .fail
    mov esi, driver_test_ok
    jmp puts
.fail:
    mov esi, driver_test_failed
    jmp puts

driver_count dd 0
driver_registry times MAX_DRIVERS dd 0
irq_callbacks times 16 dd 0
irq_owners times 16 dd 0
driver_buffer times 251 db 0
driver_states dd state_registered,state_ready,state_absent,state_failed
state_registered db 'registered',0
state_ready db 'ready',0
state_absent db 'absent',0
state_failed db 'failed',0
driver_abi_msg db 'ABI=',0
driver_error_msg db ' error=',0
ops_msg db 'Operaciones: ',0
read_msg db 'read ',0
write_msg db 'write ',0
ioctl_msg db 'ioctl ',0
bytes_msg db ' bytes escritos',10,0
bad_abi_descriptor dd 999,0,0,0,0,0,0,0,0,0
driver_test_ok db 'Driver API tests: OK (ABI, duplicados, IRQ, ioctl, limites, errores)',10,0
driver_test_failed db 'Driver API tests: FAILED',10,0

; Fixtures temporales: cuenta excesiva y probe ausente que reclama una IRQ.
driver_regression_tests:
    pushad
    mov ebp, [driver_count]
    cmp ebp, MAX_DRIVERS-2
    ja .fail
    mov ebx, count_test_driver
    call driver_register
    test eax, eax
    jnz .fail
    call driver_start
    mov edi, driver_buffer
    mov ecx, 4
    pushfd
    pop esi
    call driver_read
    cmp eax, EIO
    jne .fail
    test edx, edx
    jnz .fail
    pushfd
    pop eax
    xor eax, esi
    test eax, 0x200
    jnz .fail
    mov ebx, absent_test_driver
    call driver_register
    test eax, eax
    jnz .fail
    call driver_start
    cmp eax, ENODEV
    jne .fail
    cmp dword [absent_test_driver+D_STATE], ABSENT
    jne .fail
    cmp dword [irq_callbacks+10*4], 0
    jne .fail
    ; Solo comprobar la cascada si no habia otros propietarios secundarios.
    mov ecx, 8
.slaves:
    cmp dword [irq_callbacks+ecx*4], 0
    jne .pass
    inc ecx
    cmp ecx, 16
    jb .slaves
    in al, 0x21
    test al, 4
    jz .fail
.pass:
    xor eax, eax
    jmp .cleanup
.fail:
    mov eax, EIO
.cleanup:
    push eax
    mov ebx, absent_test_driver
    call driver_release_irqs
    mov ecx, [driver_count]
.remove:
    cmp ecx, ebp
    jbe .removed
    dec ecx
    mov dword [driver_registry+ecx*4], 0
    jmp .remove
.removed:
    mov [driver_count], ebp
    pop eax
    mov [esp+28], eax
    popad
    ret
count_test_read:
    ; No escribe fuera de limites: simula una cuenta retornada erronea.
    cli
    lea edx, [ecx+1]
    xor eax, eax
    ret
absent_test_probe:
    mov eax, 10
    mov ecx, absent_test_irq
    call irq_register
    test eax, eax
    jnz .done
    mov eax, ENODEV
.done:
    ret
absent_test_irq:
    ret
DRIVER count_test_driver, count_test_name, text_class, 0, 0, count_test_read, 0, 0
DRIVER absent_test_driver, absent_test_name, text_class, absent_test_probe, 0, 0, 0, 0
count_test_name db 'overflow_test',0
absent_test_name db 'absent_test',0
