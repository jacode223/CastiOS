OUTPUT_FORMAT(elf32-i386)
ENTRY(entries)
PHDRS { code PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
 . = 0x20000;
 .entry : { KEEP(*(.entry)) } :code
 .text : { *(.text*) } :code
 .rodata : { *(.rodata*) } :code
 . = ALIGN(32);
 .data : { *(.data*) } :data
 .runtime_state : { BYTE(0); . = ALIGN(4); *(.bss*) *(COMMON) } :data
 ASSERT(. < 0x30000, "C runtime + BSS invade kernel scratch")
 /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
