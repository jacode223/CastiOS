OUTPUT_FORMAT(elf32-i386)
ENTRY(normalize)
SECTIONS {
 . = 0x68000;
 .header : { LONG(0x4e534143); LONG(normalize); }
 .text : { *(.text*) }
 .rodata : { *(.rodata*) }
 .state : { BYTE(0); *(.data*) *(.bss*) *(COMMON) }
 ASSERT(. <= 0x6c000, "Normalizer overlaps desktop")
 .desktop 0x6c000 : { *(.desktop) }
 ASSERT(. <= 0x70000, "Castic name module too large")
 /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
