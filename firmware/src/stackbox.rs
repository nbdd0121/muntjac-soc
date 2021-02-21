use core::mem::MaybeUninit;

pub trait Array {}

pub struct S1([usize; 0]);
impl Array for S1 {}

pub struct S2([usize; 1]);
impl Array for S2 {}

pub struct S4([usize; 3]);
impl Array for S4 {}

pub struct StackBox<A: Array, T: ?Sized> {
    storage: A,
    ptr: *mut T,
}

impl<A: Array, T: ?Sized> StackBox<A, T> {
    #[doc(hidden)]
    pub unsafe fn new_from_ptr(ptr: *const T) -> Self {
        let box_size: usize = core::mem::size_of::<A>() + core::mem::size_of::<usize>();
        let size = core::mem::size_of_val(&*ptr);
        let align = core::mem::align_of_val(&*ptr);
        assert!(size <= box_size);
        assert!(align <= core::mem::align_of::<usize>());

        let mut storage = MaybeUninit::<Self>::uninit();

        let storage_u8 = storage.as_mut_ptr() as *mut u8;
        let ptr_u8 = ptr as *const u8;
        core::ptr::copy_nonoverlapping(ptr_u8, storage_u8, size);

        if core::mem::size_of::<*const T>() > core::mem::size_of::<usize>() {
            let fat = *(&ptr as *const *const T as *const usize).add(1);
            *(storage_u8.add(box_size) as *mut usize) = fat;
        }
        
        storage.assume_init()
    }

    fn as_ptr(&self) -> *const T {
        unsafe {
            let box_size: usize = core::mem::size_of::<A>() + core::mem::size_of::<usize>();
            let storage_u8 = self as *const Self as *const u8;
            let mut ret = MaybeUninit::<*const T>::uninit();
            let ret_view = ret.as_mut_ptr() as *mut usize;

            // Set address
            *ret_view = storage_u8 as usize;

            if core::mem::size_of::<*const T>() > core::mem::size_of::<usize>() {
                // Set fat
                let fat = *(storage_u8.add(box_size) as *const usize);
                *ret_view.add(1) = fat;
            }

            ret.assume_init()
        }
    }

    pub fn as_mut_ptr(&mut self) -> *mut T {
        self.as_ptr() as _
    }
}

impl<A: Array, T> StackBox<A, T> {
    pub fn new(value: T) -> Self {
        let ret = unsafe { crate::stackbox::StackBox::new_from_ptr(&value) };
        core::mem::forget(value);
        ret
    }
}

impl<A: Array, T: ?Sized> core::ops::Deref for StackBox<A, T> {
    type Target = T;
    fn deref(&self) -> &T {
        unsafe { &*self.as_ptr() }
    }
}

impl<A: Array, T: ?Sized> core::ops::DerefMut for StackBox<A, T> {
    fn deref_mut(&mut self) -> &mut T {
        unsafe { &mut*self.as_mut_ptr() }
    }
}

unsafe impl<A: Array, T: ?Sized + Send> Send for StackBox<A, T> {}
unsafe impl<A: Array, T: ?Sized + Sync> Sync for StackBox<A, T> {}

impl<A: Array, T: Clone> Clone for StackBox<A, T> {
    fn clone(&self) -> Self {
        Self::new((**self).clone())
    }
}

impl<A: Array, T: ?Sized> Drop for StackBox<A, T> {
    fn drop(&mut self) {
        unsafe { core::ptr::drop_in_place(self.as_mut_ptr()) }
    }
}


macro_rules! stackbox {
    ( $e: expr ) => {{
        let val = $e;
        let ptr = &val as _;
        let ret = unsafe { crate::stackbox::StackBox::new_from_ptr(ptr) };
        core::mem::forget(val);
        ret
    }}
}
