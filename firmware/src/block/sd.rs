#![allow(dead_code)]

use crate::io::Result as IoResult;
use crate::iomem::IoMem;
use byteorder::{ByteOrder, LE};
use spin::Mutex;

const BLK_SIZE: usize = 0x04;
const BLK_CNT: usize = 0x06;
const ARGUMENT: usize = 0x08;
const XFER_MODE: usize = 0x0C;
const CMD: usize = 0x0E;
const RESPONSE: usize = 0x10;
const BUFFER_PORT: usize = 0x20;
const PRESENT_STATE: usize = 0x24;
const HOST_CTRL: usize = 0x28;
const POWER_CTRL: usize = 0x29;
const CLOCK_CTRL: usize = 0x2C;
const TIMEOUT_CTRL: usize = 0x2E;
const SW_RESET: usize = 0x2F;
const IRQ_STATUS: usize = 0x30;
const IRQ_ENABLE: usize = 0x34;
const CAPABILITIES: usize = 0x40;

pub struct Inner {
    base: IoMem<0x80>,
    init: bool,
    ccs: bool,
    rca: u16,
}

impl Inner {
    pub const unsafe fn new(base: usize) -> Self {
        Self {
            base: IoMem::new(base),
            init: false,
            ccs: false,
            rca: 0,
        }
    }

    pub fn power_on(&mut self) {
        assert!(!self.init);
        println!("Init SD Card");
        self.rca = 0;

        // Reset controller
        self.base.write_u8(SW_RESET, 0b1);
        loop {
            let state = self.base.read_u8(SW_RESET);
            if state & 0x7 == 0 {
                break;
            }
        }

        let present = loop {
            let state = self.base.read_u32(PRESENT_STATE);
            // Wait for Card State Stable to reach 1
            if state & 0x00020000 == 0x00020000 {
                break state & 0x00010000 != 0;
            }
        };
        if !present {
            panic!("SD Card is not present");
        }
        println!("SD Card present");

        let cap = self.base.read_u32(CAPABILITIES);

        // Read base clock, must not be zero
        let base_clock = (cap >> 8) & 0b111111;
        assert_ne!(base_clock, 0);

        // Calculate the divisor to get <= 25MHz.
        let divisor = (base_clock + 24) / 25;
        assert!(divisor <= 512);
        // If divisor == 1, use the base clock, otherwise do 2x division.
        let freq_select = if divisor == 1 {
            0
        } else {
            (divisor as u16 + 1) / 2
        };

        // Turn on internal clock
        self.base.write_u16(CLOCK_CTRL, freq_select << 8 | 0b001);
        // Wait for internal clock to stabilise
        loop {
            let state = self.base.read_u16(CLOCK_CTRL);
            if state & 0b10 != 0 {
                break;
            }
        }
        // Turn on SD clock
        self.base.write_u16(CLOCK_CTRL, freq_select << 8 | 0b101);
        println!("SD clock enabled");

        // Read base clock for timeout (in kHZ)
        let base_clock = (cap & 0b111111) * if (cap >> 7) & 1 == 0 { 1 } else { 1000 };
        assert_ne!(base_clock, 0);

        // Calculate the log2(divisor) to get 500ms
        let divisor = (32 - (base_clock * 1000 - 1).leading_zeros()).max(13);
        assert!(divisor <= 27);
        self.base.write_u8(TIMEOUT_CTRL, (divisor - 13) as u8);

        // Turn on IRQ statuses
        self.base.write_u32(IRQ_ENABLE, 0x03ff_01ff);

        // Turn on SD power with voltage = 3.3V
        self.base.write_u8(POWER_CTRL, 0b1111);
        println!("SD power on");

        // Reset card
        self.wait_cmd(0, 0).expect("CMD0 shouldn't fail");

        // Voltage Check
        let resp = self
            .wait_cmd(8, 0b0001_10101010)
            .expect("Legacy SD card not supported");
        assert_eq!(resp, 0b0001_10101010);
        println!("voltage check completed");

        // ACMD41
        let resp = loop {
            let state = self.wait_app_cmd(41, 0x40300000).expect("ACMD41 failed");
            if state & 0x80000000 != 0 {
                break state;
            }
        };
        assert!(resp & 0x00300000 != 0);
        self.ccs = resp & 0x40000000 != 0;
        println!("{} detected", if self.ccs { "SDHC/SDXC" } else { "SDSC" });

        // CMD2
        self.wait_cmd(2, 0).expect("CMD2 failed");

        // CMD3
        let resp = self.wait_cmd(3, 0).expect("CMD3 failed");
        self.rca = (resp >> 16) as u16;
        println!("RCA = {:x}", self.rca);

        // Select card
        self.wait_cmd(7, (self.rca as u32) << 16)
            .expect("Cannot select card");
        // Wait for busy to deassert
        loop {
            let state = self.base.read_u32(PRESENT_STATE);
            if state & 0b10 == 0 {
                break;
            }
        }

        // Switch mode to 4-bit.
        self.wait_app_cmd(6, 0b10)
            .expect("Cannot switch to 4-bit mode");
        self.base.write_u8(HOST_CTRL, 0b10);
        println!("4-bit mode switched");

        self.base.write_u16(BLK_SIZE, 512);

        self.init = true;
    }

    pub fn power_off(&mut self) {
        // Reset controller
        self.base.write_u8(SW_RESET, 0b1);

        self.init = false;
    }

    pub fn dump_core(&mut self) {
        for i in (0..256).step_by(4) {
            let reg = self.base.read_u32(i);
            println!("[{:2x}] = {:08x}", i, reg);
        }
    }

    fn check_err(&mut self) -> Result<(), u16> {
        let irq = self.base.read_u32(IRQ_STATUS);
        if irq & 0x8000 != 0 {
            // Clear IRQs
            self.base.write_u32(IRQ_STATUS, 0x03FF0000);
            Err((irq >> 16) as u16)
        } else {
            Ok(())
        }
    }

    fn wait_cmd_with_cfg(&mut self, index: u8, argument: u32, config: u8) -> Result<u32, u16> {
        self.base.write_u32(ARGUMENT, argument);
        self.base
            .write_u16(CMD, (index as u16) << 8 | config as u16);

        loop {
            let state = self.base.read_u32(PRESENT_STATE);
            if state & 0b1 == 0 {
                break;
            }
        }

        self.check_err()?;
        Ok(self.base.read_u32(RESPONSE))
    }

    fn wait_cmd(&mut self, index: u8, argument: u32) -> Result<u32, u16> {
        let config = match index {
            // R0
            0 => 0b00000000,
            // R1
            8 => 0b00011010,
            // R1b
            7 => 0b00011011,
            // R2
            2 => 0b00001001,
            // R4
            5 => 0b00000010,
            // R6
            3 => 0b00011010,
            _ => panic!("unknown index {}", index),
        };
        self.wait_cmd_with_cfg(index, argument, config)
    }

    fn wait_app_cmd(&mut self, index: u8, argument: u32) -> Result<u32, u16> {
        let config = match index {
            // R1
            6 => 0b00011010,
            // R3
            41 => 0b00000010,
            _ => panic!("unknown index {}", index),
        };
        let resp = self
            .wait_cmd_with_cfg(55, (self.rca as u32) << 16, 0b00011010)
            .expect("cannot send APP cmd");
        assert!(resp & 1 << 5 != 0);
        self.wait_cmd_with_cfg(index, argument, config)
    }

    fn read_buffer(&mut self, data: &mut [u8]) -> Result<(), u16> {
        assert_eq!(data.len(), 512);

        // Wait for buffer to become available
        loop {
            let state = self.base.read_u32(PRESENT_STATE);
            if state & (1 << 11) != 0 {
                break;
            }
            self.check_err()?;
        }

        // Read data from buffer into data
        for chunk in data.chunks_exact_mut(4) {
            let word = self.base.read_u32(BUFFER_PORT);
            LE::write_u32(chunk, word);
        }

        Ok(())
    }

    fn write_buffer(&mut self, data: &[u8]) -> Result<(), u16> {
        assert_eq!(data.len(), 512);

        // Wait for buffer to become available
        loop {
            let state = self.base.read_u32(PRESENT_STATE);
            if state & (1 << 10) != 0 {
                break;
            }
            self.check_err()?;
        }

        // Write data into buffer
        for chunk in data.chunks_exact(4) {
            let word = LE::read_u32(&chunk);
            self.base.write_u32(BUFFER_PORT, word);
        }

        Ok(())
    }

    pub fn read_blocks(
        &mut self,
        block_addr: u32,
        block_cnt: u16,
        data: &mut [u8],
    ) -> Result<(), u16> {
        assert_ne!(block_cnt, 0);
        assert_eq!(data.len(), block_cnt as usize * 512);
        let arg = if self.ccs {
            block_addr
        } else {
            block_addr * 512
        };

        if block_cnt != 1 {
            self.base.write_u16(BLK_CNT, block_cnt);
            self.base.write_u16(XFER_MODE, 0b110110);
            self.wait_cmd_with_cfg(18, arg, 0b00111010)?;
        } else {
            self.base.write_u16(XFER_MODE, 0b010000);
            self.wait_cmd_with_cfg(17, arg, 0b00111010)?;
        }

        for chunk in data.chunks_exact_mut(512) {
            self.read_buffer(chunk)?;
        }

        // Wait for data transfer to complete
        loop {
            let state = self.base.read_u32(PRESENT_STATE);
            if state & 0b10 == 0 {
                break;
            }
        }

        self.check_err()?;
        Ok(())
    }

    pub fn write_blocks(
        &mut self,
        block_addr: u32,
        block_cnt: u16,
        data: &[u8],
    ) -> Result<(), u16> {
        assert_ne!(block_cnt, 0);
        assert_eq!(data.len(), block_cnt as usize * 512);
        let arg = if self.ccs {
            block_addr
        } else {
            block_addr * 512
        };

        if block_cnt != 1 {
            self.base.write_u16(BLK_CNT, block_cnt);
            self.base.write_u16(XFER_MODE, 0b100110);
            self.wait_cmd_with_cfg(25, arg, 0b00111010)?;
        } else {
            self.base.write_u16(XFER_MODE, 0b000000);
            self.wait_cmd_with_cfg(24, arg, 0b00111010)?;
        }

        for chunk in data.chunks_exact(512) {
            self.write_buffer(chunk)?;
        }

        // Wait for data transfer to complete
        loop {
            let state = self.base.read_u32(PRESENT_STATE);
            if state & 0b10 == 0 {
                break;
            }
        }

        self.check_err()?;
        Ok(())
    }
}

pub struct Sd(pub Mutex<Inner>);

impl Drop for Sd {
    fn drop(&mut self) {
        self.0.get_mut().power_off();
    }
}

impl Sd {
    pub const unsafe fn new(base: usize) -> Self {
        Sd(Mutex::new(Inner::new(base)))
    }

    pub fn power_on(&self) {
        self.0.lock().power_on();
    }
}

impl super::Block for Sd {
    fn read_exact_at(&self, buffer: &mut [u8], offset: u64) -> IoResult<()> {
        assert_eq!(offset % 512, 0, "offset must be sector-aligned");
        assert_eq!(buffer.len() % 512, 0, "buffer size must be sector-aligned");

        let count = buffer.len() / 512;
        let sector_id = (offset / 512) as u32;

        assert!(count <= 65536);
        let mut inner = self.0.lock();
        inner
            .read_blocks(sector_id as u32, count as u16, buffer)
            .unwrap();
        Ok(())
    }

    fn write_all_at(&self, _buf: &[u8], _offset: u64) -> IoResult<()> {
        unimplemented!();
    }

    fn len(&self) -> u64 {
        todo!();
    }
}
