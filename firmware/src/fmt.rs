#![allow(unused_macros)]

use core::fmt::Write;

pub struct Console;

pub static CONSOLE: spin::Mutex<Console> = spin::Mutex::new(Console);

impl Write for Console {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for byte in s.bytes() {
            if byte == b'\n' {
                super::uart::uart_send_byte(b'\r');
            }
            super::uart::uart_send_byte(byte);
        }
        Ok(())
    }
}

pub fn console_write(args: core::fmt::Arguments<'_>) {
    CONSOLE.lock().write_fmt(args).unwrap();
}

macro_rules! format_args_nl {
    ($fmt:expr) => (format_args!(concat!($fmt, "\n")));
    ($fmt:expr, $($args:tt)* ) => (format_args!(concat!($fmt, "\n"), $($args)*));
}

macro_rules! println {
    ($($args:tt)*) => ({
        crate::fmt::console_write(format_args_nl!($($args)*))
    })
}

macro_rules! print {
    ($($arg:tt)*) => ({
        crate::fmt::console_write(format_args!($($arg)*))
    })
}

macro_rules! dbg {
    () => {
        println!("[{}:{}]", file!(), line!());
    };
    ($val:expr) => {
        // Use of `match` here is intentional because it affects the lifetimes
        // of temporaries - https://stackoverflow.com/a/48732525/1063961
        match $val {
            tmp => {
                println!("[{}:{}] {} = {:#?}",
                    file!(), line!(), stringify!($val), &tmp);
                tmp
            }
        }
    };
    // Trailing comma with single argument is ignored
    ($val:expr,) => { dbg!($val) };
    ($($val:expr),+ $(,)?) => {
        ($(dbg!($val)),+,)
    };
}

struct Logger;

impl log::Log for Logger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Debug
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            let color = match record.level() {
                log::Level::Trace => "35",
                log::Level::Debug => "34",
                log::Level::Info => "32",
                log::Level::Warn => "33",
                log::Level::Error => "31",
            };
            println!(
                "\x1b[{color}m{level}:{target}:{msg}\x1b[0m",
                color = color,
                level = record.level(),
                target = record.target(),
                msg = record.args()
            );
        }
    }
    fn flush(&self) {}
}

pub fn logger_init() {
    log::set_logger(&Logger).unwrap();
    log::set_max_level(log::LevelFilter::Trace);
}

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    println!("{}", info);
    super::abort();
}
