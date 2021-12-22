OUTPUT_FORMAT("elf64-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = ${MEMORY_LIMIT} - 0x200000;

  __text_start = .;
  __executable_start = .;
  .text.start : { *(.text.start) }

  .text           :
  {
    *(.text.unlikely .text.unlikely.*)
    *(.text.startup .text.startup.*)
    *(.text .text.*)
  }
  PROVIDE (__etext = .);
  PROVIDE (_etext = .);
  PROVIDE (etext = .);
  .rodata         : { *(.rodata .rodata.*) }
  .sdata2         :
  {
    *(.sdata2 .sdata2.*)
  }
  .sbss2          : { *(.sbss2 .sbss2.*) }
  . = ALIGN(64 / 8);
  .eh_frame_hdr   : { *(.eh_frame_hdr) *(.eh_frame_entry .eh_frame_entry.*) }
  .eh_frame       : { KEEP (*(.eh_frame)) *(.eh_frame.*) }
  .gcc_except_table   : { *(.gcc_except_table .gcc_except_table.*) }

  . = ALIGN(8);

  /* Thread Local Storage sections  */
  .tdata :
  {
    __tdata_start = .;
    *(.tdata .tdata.*)
    . = ALIGN(8);
    __tdata_end = .;
  }
  .tbss :
  {
    *(.tbss .tbss.*)
    . = ALIGN(8);
    __tbss_end = .;
  }

  . = ALIGN(8);

  __data_loc = .;

  /* DATA SECTIONS */
  .data :
  {
    __DATA_BEGIN__ = .;
    *(.data .data.*)
    /* We want the small data sections together, so single-instruction offsets
       can access them all, and initialized data all before uninitialized, so
       we can shorten the on-disk segment size.  */
    __SDATA_BEGIN__ = .;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata .srodata.*)
    *(.sdata .sdata.*)
  }

  /* Align the start */
  . = ALIGN(64 / 8);
  __bss_start = .;
  .bss :
  {
    *(.sbss .sbss.*)
    *(.bss .bss.*)
  }
  . = ALIGN(64 / 8);
  __BSS_END__ = .;
    __global_pointer$ = MIN(__SDATA_BEGIN__ + 0x800,
		            MAX(__DATA_BEGIN__ + 0x800, __BSS_END__ - 0x800));
  _end = .; PROVIDE (end = .);

  /* DWARF debug sections.
     Symbols in the DWARF debugging sections are relative to the beginning
     of the section so we begin them at 0.  */
  .debug_aranges  0 : { *(.debug_aranges) }
  .debug_pubnames 0 : { *(.debug_pubnames) }
  .debug_info     0 : { *(.debug_info) }
  .debug_abbrev   0 : { *(.debug_abbrev) }
  .debug_line     0 : { *(.debug_line) }
  .debug_frame    0 : { *(.debug_frame) }
  .debug_str      0 : { *(.debug_str) }
  .debug_loc      0 : { *(.debug_loc) }
  .debug_macinfo  0 : { *(.debug_macinfo) }
  /* DWARF 3 */
  .debug_pubtypes 0 : { *(.debug_pubtypes) }
  .debug_ranges   0 : { *(.debug_ranges) }
  /* DWARF 5  */
  .debug_addr     0 : { *(.debug_addr) }
  .debug_line_str 0 : { *(.debug_line_str) }
  .debug_loclists 0 : { *(.debug_loclists) }
  .debug_macro    0 : { *(.debug_macro) }
  .debug_names    0 : { *(.debug_names) }
  .debug_rnglists 0 : { *(.debug_rnglists) }
  .debug_str_offsets 0 : { *(.debug_str_offsets) }
  .debug_sup      0 : { *(.debug_sup) }

  /DISCARD/ : { *.* }
}

