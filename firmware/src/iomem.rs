use core::mem;
use core::ptr;

#[derive(Clone, Copy)]
pub struct IoMem<const SIZE: usize> {
    ptr: usize,
}

impl<const SIZE: usize> IoMem<SIZE> {
    #[inline]
    pub const unsafe fn new(ptr: usize) -> Self {
        Self { ptr }
    }

    #[inline]
    pub fn read<T: Copy>(&self, offset: usize) -> T {
        assert!(offset + mem::size_of::<T>() <= SIZE);
        assert!(offset % mem::align_of::<T>() == 0);
        unsafe { ptr::read_volatile((self.ptr + offset) as *const T) }
    }

    #[inline]
    pub fn read_u8(&self, offset: usize) -> u8 {
        self.read(offset)
    }

    #[inline]
    pub fn read_u16(&self, offset: usize) -> u16 {
        self.read(offset)
    }

    #[inline]
    pub fn read_u32(&self, offset: usize) -> u32 {
        self.read(offset)
    }

    #[inline]
    pub fn read_u64(&self, offset: usize) -> u64 {
        self.read(offset)
    }

    #[inline]
    pub fn write<T: Copy>(&self, offset: usize, value: T) {
        assert!(offset + mem::size_of::<T>() <= SIZE);
        assert!(offset % mem::align_of::<T>() == 0);
        unsafe { ptr::write_volatile((self.ptr + offset) as *mut T, value) };
    }

    #[inline]
    pub fn write_u8(&self, offset: usize, value: u8) {
        self.write(offset, value)
    }

    #[inline]
    pub fn write_u16(&self, offset: usize, value: u16) {
        self.write(offset, value)
    }

    #[inline]
    pub fn write_u32(&self, offset: usize, value: u32) {
        self.write(offset, value)
    }

    #[inline]
    pub fn write_u64(&self, offset: usize, value: u64) {
        self.write(offset, value)
    }
}
