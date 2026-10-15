OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) }
  . = ALIGN(4);
  .rodata : { *(.rodata .rodata.*) }
  . = ALIGN(4);
  .data : { *(.data .data.*) *(.sdata .sdata.*) }
  .bss (NOLOAD) : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) }
  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
