OUTPUT_ARCH(riscv)
ENTRY(_start)
PHDRS {
  code PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}
SECTIONS {
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) } :code
  /* Scalar/SIMD inputs have exactly the same addresses and cache set mapping. */
  . = 0x80020000;
  .rodata : { *(.rodata .rodata.*) } :data
  . = ALIGN(32);
  .data : { *(.data .data.*) *(.sdata .sdata.*) } :data
  .bss (NOLOAD) : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) } :data
  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
