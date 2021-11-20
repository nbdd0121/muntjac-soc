#![allow(non_camel_case_types)]
#![allow(unused)]

type Elf64_Half = u16;
type Elf64_Word = u32;
type Elf64_Off = u64;
type Elf64_Addr = u64;
type Elf64_Xword = u64;
type Elf64_Sxword = i64;

const PT_LOAD: u32 = 1;

#[repr(C)]
struct Elf64_Ehdr {
    pub e_ident: [u8; 16],
    pub e_type: Elf64_Half,
    pub e_machine: Elf64_Half,
    pub e_version: Elf64_Word,
    pub e_entry: Elf64_Addr,
    pub e_phoff: Elf64_Off,
    pub e_shoff: Elf64_Off,
    pub e_flags: Elf64_Word,
    pub e_ehsize: Elf64_Half,
    pub e_phentsize: Elf64_Half,
    pub e_phnum: Elf64_Half,
    pub e_shentsize: Elf64_Half,
    pub e_shnum: Elf64_Half,
    pub e_shstrndx: Elf64_Half,
}

#[repr(C)]
struct Elf64_Phdr {
    pub p_type: Elf64_Word,
    pub p_flags: Elf64_Word,
    pub p_offset: Elf64_Off,
    pub p_vaddr: Elf64_Addr,
    pub p_paddr: Elf64_Addr,
    pub p_filesz: Elf64_Xword,
    pub p_memsz: Elf64_Xword,
    pub p_align: Elf64_Xword,
}

const PF_R: u32 = 0x4;
const PF_W: u32 = 0x2;
const PF_X: u32 = 0x1;
const ET_EXEC: Elf64_Half = 2;
const ET_DYN: Elf64_Half = 3;
const EM_RISCV: Elf64_Half = 243;

#[repr(C)]
struct Loader {
    memory: *const u8,
}

struct PhdrIter<'a> {
    i: usize,
    ehdr: &'a Elf64_Ehdr,
}

impl<'a> Iterator for PhdrIter<'a> {
    type Item = &'a Elf64_Phdr;
    fn next(&mut self) -> Option<Self::Item> {
        if self.i == self.ehdr.e_phnum as usize {
            None
        } else {
            let ptr = self.ehdr as *const _ as usize
                + self.ehdr.e_phoff as usize
                + self.ehdr.e_phentsize as usize * self.i;
            self.i += 1;
            Some(unsafe { &*(ptr as *const Elf64_Phdr) })
        }
    }
}

impl Loader {
    fn ehdr(&self) -> &Elf64_Ehdr {
        unsafe { &*(self.memory as *const Elf64_Ehdr) }
    }

    fn phdr(&self) -> PhdrIter {
        PhdrIter {
            i: 0,
            ehdr: self.ehdr(),
        }
    }

    pub fn new(ptr: *const u8) -> Loader {
        // Must be properly aligned.
        assert!(ptr as usize % 8 == 0);
        Loader { memory: ptr }
    }

    unsafe fn load_kernel(&self, load_addr: u64) -> u64 {
        let header = self.ehdr();

        // Check the ELF magic numbers
        if &header.e_ident[0..4] != "\x7FELF".as_bytes() {
            panic!("Not ELF file")
        }

        // We can only proceed with executable or dynamic binary.
        if header.e_type != ET_EXEC && header.e_type != ET_DYN {
            panic!("the binary is not executable.");
        }

        // Check that the ELF is for RISC-V
        if header.e_machine != EM_RISCV {
            panic!("the binary is not for RISC-V.");
        }

        // Scan the bounds of the image.
        let mut loaddr = u64::max_value();
        let mut hiaddr = 0;
        for h in self.phdr() {
            if h.p_type == PT_LOAD {
                loaddr = core::cmp::min(loaddr, h.p_vaddr);
                hiaddr = core::cmp::max(hiaddr, h.p_vaddr + h.p_memsz);
            }
        }

        loaddr &= !4095;
        hiaddr = (hiaddr + 4095) & !4095;

        for h in self.phdr() {
            if h.p_type == PT_LOAD {
                // size in memory cannot be smaller than size in file
                if h.p_filesz > h.p_memsz {
                    panic!("invalid elf file: constraint p_filesz <= p_memsz is not satisified");
                }

                // Copy across.
                core::ptr::copy_nonoverlapping(
                    (self.memory as usize + h.p_offset as usize) as *const u8,
                    (h.p_vaddr - loaddr + load_addr) as usize as *mut u8,
                    h.p_filesz as usize,
                );

                // Zero-out the rest
                core::ptr::write_bytes(
                    (h.p_vaddr + h.p_filesz - loaddr + load_addr) as usize as *mut u8,
                    0,
                    (h.p_memsz - h.p_filesz) as usize,
                );
            }
        }

        hiaddr - loaddr
    }
}

pub unsafe fn load_elf(slice: &[u8], addr: usize) -> usize {
    Loader::new(slice.as_ptr()).load_kernel(addr as _) as _
}
