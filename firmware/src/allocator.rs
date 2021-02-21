//! Scoped allocator.
//!
//! Scoped allocator has nested scopes. Within each scope, it allocates in a linear incremental
//! fashion and never performs any deallocation. It will however track whether the number of items
//! yet to deallocate. When scope ends, it will check if everything allocated within the scope is
//! deallocated, and panic if not.

use core::alloc::{GlobalAlloc, Layout};
use spin::Mutex;

struct MemoryBlock {
    ptr: usize,
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
            None => panic!("no allocation scope active"),
            Some(ref mut block) => {
                let ret = (block.ptr + layout.align() - 1) & !(layout.align() - 1);
                let new_ptr = ret + layout.size();
                if new_ptr > block.end {
                    return core::ptr::null_mut();
                }
                block.ptr = new_ptr;
                block.num += 1;
                ret as _
            }
        }
    }
    unsafe fn dealloc(&self, ptr: *mut u8, _layout: Layout) {
        let ptr = ptr as usize;

        let mut guard = self.0.lock();
        let mut block = guard.as_deref_mut();
        while let Some(cur_block) = block {
            if ptr >= cur_block.start && ptr < cur_block.end {
                cur_block.num -= 1;
                return;
            }
            block = cur_block.parent.as_deref_mut();
        }
    }
}

#[global_allocator]
static A: ScopedAllocator = ScopedAllocator(Mutex::new(None));

#[allow(dead_code)]
pub fn scoped_with_memory<R, F: FnOnce() -> R>(mem: &mut [u8], f: F) -> R {
    let mut guard = A.0.lock();
    let mut memory_block = MemoryBlock {
        ptr: mem.as_ptr() as usize,
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
        ptr: parent.ptr,
        start: parent.ptr,
        end: parent.end,
        num: 0,
        parent: Some(parent),
    };

    *guard = Some(unsafe { &mut *(&mut memory_block as *mut MemoryBlock) });
    drop(guard);

    let ret = f();

    guard = A.0.lock();
    *guard = memory_block.parent;

    assert!(memory_block.num == 0, "some allocations are leaked");
    ret
}
