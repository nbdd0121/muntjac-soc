use core::cell::{Cell, UnsafeCell};
use core::ffi::c_void;
use core::mem::MaybeUninit;
use core::panic::PanicInfo;
use unwinding::{abi::*, panicking};

#[thread_local]
static PANIC_COUNT: Cell<usize> = Cell::new(0);

#[thread_local]
static EXCEPTION_STORAGE: UnsafeCell<MaybeUninit<UnwindException>> =
    UnsafeCell::new(MaybeUninit::uninit());

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

struct Panic;

unsafe impl panicking::Exception for Panic {
    const CLASS: [u8; 8] = *b"noneRUST";

    fn wrap(_: Self) -> *mut UnwindException {
        EXCEPTION_STORAGE.get() as *mut UnwindException
    }

    unsafe fn unwrap(_: *mut UnwindException) -> Self {
        Panic
    }
}

#[panic_handler]
pub fn panic(info: &PanicInfo<'_>) -> ! {
    println!("{}", info);
    stack_trace();

    // Update panic count.
    if PANIC_COUNT.get() >= 1 {
        println!("panicked while processing panic. aborting.");
    }
    PANIC_COUNT.set(1);

    match panicking::begin_panic(Panic) {
        UnwindReasonCode::END_OF_STACK => {
            println!("uncaught exception, aborting.");
        }
        code => println!("failed to initiate panic, error {}", code.0),
    }
    super::abort();
}

#[allow(dead_code)]
pub fn catch_unwind<R, F: FnOnce() -> R>(f: F) -> Result<R, ()> {
    panicking::catch_unwind::<Panic, _, _>(f).map_err(|_| ())
}
