// Workaround before const_in_array_repeat_expressions stablises.
macro_rules! repeat {
    ($ty: ty => $init: expr; $size: expr) => {{
        type T = $ty;
        const N: usize = $size;
        const I: T = $init;

        use core::mem::{self, MaybeUninit};

        unsafe {
            let mut data: [MaybeUninit<T>; N] = mem::transmute(MaybeUninit::<[T; N]>::uninit());
            let mut i = 0;
            while i < N {
                data[i] = MaybeUninit::new(I);
                i += 1;
            }
            mem::transmute::<_, [$ty; N]>(data)
        }
    }};
}

pub struct HartLocalKey<T: 'static> {
    #[doc(hidden)]
    pub storage: &'static [T; crate::address::MAX_HART_COUNT],
}

unsafe impl<T: 'static> Sync for HartLocalKey<T> {}

impl<T: 'static> core::ops::Deref for HartLocalKey<T> {
    type Target = T;

    fn deref(&self) -> &T {
        &self.storage[crate::hartid()]
    }
}

macro_rules! hart_local {
    () => {};
    ($(#[$attr:meta])* $vis:vis static $name:ident: $t:ty = $init:expr; $($rest:tt)*) => (
        $(#[$attr])* $vis static $name: $crate::util::HartLocalKey<$t> = {
            static mut STORAGE: [$t; $crate::address::MAX_HART_COUNT] = repeat![$t => $init; $crate::address::MAX_HART_COUNT];
            $crate::util::HartLocalKey {
                storage: unsafe { &STORAGE },
            }
        };
        hart_local!($($rest)*);
    );
}

use alloc::boxed::Box;
use alloc::vec::Vec;
use core::ptr;
use core::{cell::UnsafeCell, convert::TryInto, mem::MaybeUninit};
use spin::Mutex;

pub struct OnceCell<T> {
    ready: Mutex<bool>,
    data: UnsafeCell<MaybeUninit<T>>,
}

impl<T> Drop for OnceCell<T> {
    fn drop(&mut self) {
        if *self.ready.get_mut() {
            unsafe {
                ptr::drop_in_place((*self.data.get()).as_mut_ptr());
            }
        }
    }
}

unsafe impl<T: Send> Send for OnceCell<T> {}
unsafe impl<T: Send + Sync> Sync for OnceCell<T> {}

impl<T> OnceCell<T> {
    pub const fn new() -> Self {
        OnceCell {
            ready: Mutex::new(false),
            data: UnsafeCell::new(MaybeUninit::uninit()),
        }
    }

    pub fn get_or_try_init<F, E>(&self, f: F) -> Result<&T, E>
    where
        F: FnOnce() -> Result<T, E>,
    {
        let mut guard = self.ready.lock();
        if !*guard {
            let val = f()?;
            *guard = true;
            unsafe { ptr::write((*self.data.get()).as_mut_ptr(), val) };
        }
        Ok(unsafe { &*(*self.data.get()).as_ptr() })
    }
}

pub unsafe fn uninit_vec<T>(len: usize) -> Vec<T> {
    let mut vec = Vec::with_capacity(len);
    vec.set_len(len);
    vec
}

pub unsafe fn uninit_slice<T>(len: usize) -> Box<[T]> {
    uninit_vec(len).into_boxed_slice()
}

pub unsafe fn uninit_array<T, const N: usize>() -> Box<[T; N]> {
    uninit_slice(N).try_into().map_err(|_| ()).unwrap()
}

pub unsafe fn zeroed_slice<T>(len: usize) -> Box<[T]> {
    let mut vec = uninit_slice(len);
    ptr::write_bytes(vec.as_mut_ptr(), 0, len);
    vec
}
