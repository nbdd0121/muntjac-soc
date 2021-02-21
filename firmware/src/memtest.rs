use core::mem::size_of;

/// Test a range of memory for errors.
pub fn memtest(range: &mut [usize]) {
    let min = range.as_ptr() as usize;
    let max = min + range.len() * core::mem::size_of::<usize>();

    println!("Memory check in progress");
    println!("Writing...");
    for page in range.chunks_mut(0x200000 / size_of::<usize>()) {
        for dword in page {
            unsafe { core::ptr::write_volatile(dword, dword as *mut usize as usize) };
        }
        print!(".");
    }
    println!("\nReading...");
    for page in (min..max).step_by(0x200000) {
        for dword in (page..(page + 0x200000)).step_by(8) {
            let read = unsafe { core::ptr::read_volatile(dword as *mut usize) };
            if read != dword {
                println!("Incorrect value: {:x} = {:x}", dword, read);
                return;
            }
        }
        print!(".");
    }
    println!("\nMemory check completed");
}
