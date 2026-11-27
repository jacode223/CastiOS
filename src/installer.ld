OUTPUT_FORMAT(elf32-i386)
ENTRY(installer_entry)
SECTIONS {
 . = 0x70000;
 .header : { LONG(0x534e4943); LONG(installer_entry); }
 .text : { *(.text*) }
 .rodata : { *(.rodata*) }
 .data : { *(.data*) }
 .state : { BYTE(0); *(.bss*) *(COMMON) }
 ASSERT(. <= 0x80000, "Live installer exceeds reserved 64 KiB")
 /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
