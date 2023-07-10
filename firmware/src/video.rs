const CR_ENABLE: usize = 0x0000;
const CR_PXLFREQ: usize = 0x0004;
const CR_POLARITY: usize = 0x0008;
const CR_H_TOTAL: usize = 0x20;
const CR_H_END_DISP: usize = 0x24;
const CR_H_SRT_SYNC: usize = 0x28;
const CR_H_END_SYNC: usize = 0x2C;
const CR_V_TOTAL: usize = 0x30;
const CR_V_END_DISP: usize = 0x34;
const CR_V_SRT_SYNC: usize = 0x38;
const CR_V_END_SYNC: usize = 0x3C;

const CR_FB_COMMIT: usize = 0x40;
const CR_FB_BASE: usize = 0x48;
const CR_FB_WIDTH: usize = 0x50;
const CR_FB_HEIGHT: usize = 0x54;
const CR_FB_DEPTH: usize = 0x58;
const CR_FB_BPL: usize = 0x5C;
const CR_BG_COLOR: usize = 0x60;

#[derive(Clone, Copy)]
enum Polarity {
    Positive = 0,
    Negative = 1,
}

struct Mode {
    freq: u32,
    width: u32,
    hsync_start: u32,
    hsync_end: u32,
    htotal: u32,
    height: u32,
    vsync_start: u32,
    vsync_end: u32,
    vtotal: u32,
    hpol: Polarity,
    vpol: Polarity,
}

#[inline]
fn reg(addr: usize) -> *mut u32 {
    (crate::address::DISPLAY_BASE + addr) as _
}

fn set_mode(mode: &Mode) {
    // We currently have a fixed pixel clock at 74 MHz.
    // Check that the requested frequency is within 1% of that.
    assert!(
        mode.freq >= 73_260_000 && mode.freq <= 74_740_000,
        "Requested frequency of {} Hz cannot be achieved",
        mode.freq
    );

    unsafe {
        // Disable display.
        core::ptr::write_volatile(reg(CR_ENABLE), 0);
        // Confirm that display is disabled.
        while core::ptr::read_volatile(reg(CR_ENABLE)) != 0 {}

        core::ptr::write_volatile(reg(CR_POLARITY), mode.hpol as u32 | (mode.vpol as u32) << 1);
        core::ptr::write_volatile(reg(CR_H_END_DISP), mode.width);
        core::ptr::write_volatile(reg(CR_H_SRT_SYNC), mode.hsync_start);
        core::ptr::write_volatile(reg(CR_H_END_SYNC), mode.hsync_end);
        core::ptr::write_volatile(reg(CR_H_TOTAL), mode.htotal);
        core::ptr::write_volatile(reg(CR_V_END_DISP), mode.height);
        core::ptr::write_volatile(reg(CR_V_SRT_SYNC), mode.vsync_start);
        core::ptr::write_volatile(reg(CR_V_END_SYNC), mode.vsync_end);
        core::ptr::write_volatile(reg(CR_V_TOTAL), mode.vtotal);
    }
}

fn turn_on() {
    unsafe {
        core::ptr::write_volatile(reg(CR_ENABLE), 1);
    }
}

const MODE_720P_60HZ: Mode = Mode {
    freq: 74_250_000,
    width: 1280,
    hsync_start: 1390,
    hsync_end: 1430,
    htotal: 1650,
    height: 720,
    vsync_start: 725,
    vsync_end: 730,
    vtotal: 750,
    hpol: Polarity::Positive,
    vpol: Polarity::Positive,
};

const MODE_1080P_30HZ: Mode = Mode {
    freq: 74_250_000,
    width: 1920,
    hsync_start: 2008,
    hsync_end: 2052,
    htotal: 2200,
    height: 1080,
    vsync_start: 1084,
    vsync_end: 1089,
    vtotal: 1125,
    hpol: Polarity::Positive,
    vpol: Polarity::Positive,
};

const MODE_1080P_60HZ: Mode = Mode {
    freq: 148_500_000,
    width: 1920,
    hsync_start: 2008,
    hsync_end: 2052,
    htotal: 2200,
    height: 1080,
    vsync_start: 1084,
    vsync_end: 1089,
    vtotal: 1125,
    hpol: Polarity::Positive,
    vpol: Polarity::Positive,
};

pub fn init() {
    unsafe {
        core::ptr::write_volatile(
            reg(CR_FB_BASE) as *mut usize,
            crate::address::FRAMEBUFFER_BASE,
        );
        core::ptr::write_volatile(reg(CR_FB_WIDTH), 1280);
        core::ptr::write_volatile(reg(CR_FB_HEIGHT), 720);
        // r5g6b5
        core::ptr::write_volatile(reg(CR_FB_DEPTH), 1);
        core::ptr::write_volatile(reg(CR_FB_BPL), 1280 * 2);
        core::ptr::write_volatile(reg(CR_FB_COMMIT), 1);
    }

    set_mode(&MODE_720P_60HZ);
    turn_on();
}
