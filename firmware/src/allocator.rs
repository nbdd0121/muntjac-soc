//! Scoped allocator.
//!
//! Scoped allocator has nested scopes. Within each scope, it allocates in a linear incremental
//! fashion and never performs any deallocation. It will however track whether the number of items
//! yet to deallocate. When scope ends, it will check if everything allocated within the scope is
//! deallocated, and panic if not.

use buddy::BuddyAllocator;
use core::alloc::{GlobalAlloc, Layout};
use ro_cell::RoCell;
use spin::Mutex;

// SAFETY: This is initialized in `init`.
static FIRMWARE_ALLOC: RoCell<buddy::BuddyAllocator> = unsafe { RoCell::new_uninit() };

struct MemoryBlock {
    alloc: Option<buddy::BuddyAllocator<'static>>,
    start: usize,
    end: usize,
    num: usize,
    parent: Option<&'static mut MemoryBlock>,
}

struct ScopedAllocator(Mutex<Option<&'static mut MemoryBlock>>);

unsafe impl GlobalAlloc for ScopedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let mut guard = self.0.lock();
        match *guard {
            None => FIRMWARE_ALLOC.alloc(layout),
            Some(ref mut block) => {
                let ptr = block.alloc.as_ref().unwrap().alloc(layout);
                if !ptr.is_null() {
                    block.num += 1;
                }
                ptr
            }
        }
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        let ptr = ptr as usize;

        let mut guard = self.0.lock();
        let mut block = guard.as_deref_mut();
        while let Some(cur_block) = block {
            if ptr >= cur_block.start && ptr < cur_block.end {
                cur_block.num -= 1;
                cur_block.alloc.as_ref().unwrap().dealloc(ptr as _, layout);
                return;
            }
            block = cur_block.parent.as_deref_mut();
        }

        FIRMWARE_ALLOC.dealloc(ptr as _, layout);
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // Reallocation must happen with the original allocator.
        let ptr = ptr as usize;

        let mut guard = self.0.lock();
        let mut block = guard.as_deref_mut();
        while let Some(cur_block) = block {
            if ptr >= cur_block.start && ptr < cur_block.end {
                return cur_block
                    .alloc
                    .as_ref()
                    .unwrap()
                    .realloc(ptr as _, layout, new_size);
            }
            block = cur_block.parent.as_deref_mut();
        }

        FIRMWARE_ALLOC.realloc(ptr as _, layout, new_size)
    }
}

#[global_allocator]
static A: ScopedAllocator = ScopedAllocator(Mutex::new(None));

#[allow(dead_code)]
pub fn scoped_with_memory<R, F: FnOnce() -> R>(mem: &mut [u8], f: F) -> R {
    let buddy = BuddyAllocator::new(unsafe { core::mem::transmute(&mut *mem) }).unwrap();
    let mut guard = A.0.lock();
    let mut memory_block = MemoryBlock {
        alloc: Some(buddy),
        start: mem.as_ptr() as usize,
        end: mem.as_ptr() as usize + mem.len(),
        num: 0,
        parent: guard.take(),
    };

    *guard = Some(unsafe { &mut *(&mut memory_block as *mut MemoryBlock) });
    drop(guard);

    let ret = f();

    guard = A.0.lock();
    *guard = memory_block.parent;

    assert!(memory_block.num == 0, "some allocations are leaked");
    ret
}

#[allow(dead_code)]
pub fn scoped<R, F: FnOnce() -> R>(f: F) -> R {
    let mut guard = A.0.lock();
    let parent = guard.take().expect("no allocation scope active");
    let mut memory_block = MemoryBlock {
        alloc: parent.alloc.take(),
        start: parent.start,
        end: parent.end,
        num: 0,
        parent: Some(parent),
    };

    *guard = Some(unsafe { &mut *(&mut memory_block as *mut MemoryBlock) });
    drop(guard);

    let ret = f();

    guard = A.0.lock();
    let parent = memory_block.parent.unwrap();
    parent.alloc = memory_block.alloc;
    *guard = Some(parent);

    assert!(memory_block.num == 0, "some allocations are leaked");
    ret
}

pub fn init() {
    extern "C" {
        static _end: u8;
    }
    // Account for the stack size
    let firmware_memory_end = crate::address::MEMORY_BASE + crate::address::MEMORY_SIZE
        - (1 << 14) * crate::ipi::hart_count();
    let firmware_memory_start = unsafe { &_end as *const u8 as usize };
    let free_memory = unsafe {
        core::slice::from_raw_parts_mut(
            firmware_memory_start as _,
            firmware_memory_end - firmware_memory_start,
        )
    };

    let alloc = buddy::BuddyAllocator::new(free_memory).unwrap();
    unsafe { RoCell::init(&FIRMWARE_ALLOC, alloc) };
}
