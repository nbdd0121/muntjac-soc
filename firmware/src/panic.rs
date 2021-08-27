use core::cell::{Cell, UnsafeCell};
use core::ffi::c_void;
use core::mem::ManuallyDrop;
use core::mem::MaybeUninit;
use core::panic::PanicInfo;
use unwind::abi::*;

hart_local! {
    static PANIC_COUNT: Cell<usize> = Cell::new(0);
    static EXCEPTION_STORAGE: UnsafeCell<MaybeUninit<UnwindException>> = UnsafeCell::new(MaybeUninit::uninit());
}

fn stack_trace() {
    struct CallbackData {
        counter: usize,
    }
    extern "C" fn callback(
        unwind_ctx: &mut UnwindContext<'_>,
        arg: *mut c_void,
    ) -> UnwindReasonCode {
        let data = unsafe { &mut *(arg as *mut CallbackData) };
        data.counter += 1;
        println!("{:4}:{:#19x}", data.counter, _Unwind_GetIP(unwind_ctx));
        UnwindReasonCode::NO_REASON
    }
    let mut data = CallbackData { counter: 0 };
    _Unwind_Backtrace(callback, &mut data as *mut _ as _);
}

const EXCEPTION_CLASS: u64 = u64::from_be_bytes(*b"garyRUST");

#[panic_handler]
pub fn panic(info: &PanicInfo<'_>) -> ! {
    println!("{}", info);
    stack_trace();

    // Update panic count.
    if PANIC_COUNT.get() >= 1 {
        println!("panicked while processing panic. aborting.");
    }
    PANIC_COUNT.set(1);

    let mut unwind_ex = UnwindException::new();
    unwind_ex.exception_class = EXCEPTION_CLASS;
    unwind_ex.exception_cleanup = None;
    let exception = EXCEPTION_STORAGE.get() as *mut UnwindException;
    unsafe { exception.write(unwind_ex) }
    let code = _Unwind_RaiseException(unsafe { &mut *exception });

    match code {
        UnwindReasonCode::END_OF_STACK => {
            println!("uncaught exception, aborting.");
        }
        _ => println!("failed to initiate panic, error {}", code.0),
    }
    super::abort();
}

pub fn catch_unwind<R, F: FnOnce() -> R>(f: F) -> Result<R, ()> {
    union Data<F, R> {
        f: ManuallyDrop<F>,
        r: ManuallyDrop<R>,
    }

    let mut data = Data {
        f: ManuallyDrop::new(f),
    };

    let data_ptr = &mut data as *mut _ as *mut u8;
    unsafe {
        return if core::intrinsics::r#try(do_call::<F, R>, data_ptr, do_catch::<F, R>) == 0 {
            Ok(ManuallyDrop::into_inner(data.r))
        } else {
            Err(())
        };
    }

    #[inline]
    fn do_call<F: FnOnce() -> R, R>(data: *mut u8) {
        unsafe {
            let data = data as *mut Data<F, R>;
            let data = &mut (*data);
            let f = ManuallyDrop::take(&mut data.f);
            data.r = ManuallyDrop::new(f());
        }
    }

    #[inline]
    fn do_catch<F: FnOnce() -> R, R>(_data: *mut u8, _payload: *mut u8) {}
}
