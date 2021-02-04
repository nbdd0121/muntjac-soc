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
