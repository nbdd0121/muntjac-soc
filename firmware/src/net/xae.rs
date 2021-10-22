#![allow(dead_code)]

use smoltcp::phy::{self, Checksum, DeviceCapabilities};
use smoltcp::time::Instant;
use smoltcp::{Error, Result};

use crate::iomem::IoMem;
use crate::util::{uninit_array, zeroed_slice};
use alloc::boxed::Box;
use core::slice;
use core::{cell::UnsafeCell, mem::MaybeUninit, time::Duration};

#[repr(C, align(0x40))]
struct Descriptor {
    next_desc: *mut Descriptor,
    buffer_address: *mut u8,
    reserved: u64,
    control: u32,
    status: u32,
    app: [u32; 5],
    buffer: Option<Box<[MaybeUninit<u8>; 1514]>>,
}

const DMA_MM2S_DMACR_OFFSET: usize = 0x00;
const DMA_MM2S_DMASR_OFFSET: usize = 0x04;
const DMA_MM2S_CURDESC_OFFSET: usize = 0x08;
const DMA_MM2S_TAILDESC_OFFSET: usize = 0x10;
const DMA_SG_CTL_OFFSET: usize = 0x2C;
const DMA_S2MM_DMACR_OFFSET: usize = 0x30;
const DMA_S2MM_DMASR_OFFSET: usize = 0x34;
const DMA_S2MM_CURDESC_OFFSET: usize = 0x38;
const DMA_S2MM_TAILDESC_OFFSET: usize = 0x40;

const DMA_IRQ_IOC: u32 = 1 << 12;
const DMA_IRQ_DELAY: u32 = 1 << 13;
const DMA_IRQ_ERROR: u32 = 1 << 14;
const DMA_IRQ_ALL: u32 = DMA_IRQ_IOC | DMA_IRQ_DELAY | DMA_IRQ_ERROR;

const DMA_CR_RUNSTOP: u32 = 1 << 0;
const DMA_CR_RESET: u32 = 1 << 2;

const DMA_CR_COALESCE_MASK: u32 = 0x00FF0000;
const DMA_CR_DELAY_MASK: u32 = 0xFF000000;

const DMA_CR_COALESCE_SHIFT: u32 = 16;
const DMA_CR_DELAY_SHIFT: u32 = 24;

const DMA_SR_HALT: u32 = 1 << 0;

const ETH_IE_OFFSET: usize = 0x14;
const ETH_RCW1_OFFSET: usize = 0x404;
const ETH_TC_OFFSET: usize = 0x408;
const ETH_FCC_OFFSET: usize = 0x40C;
const ETH_UAW0_OFFSET: usize = 0x700;
const ETH_UAW1_OFFSET: usize = 0x704;

const ETH_RCW1_RX: u32 = 1 << 28;
const ETH_TC_TX: u32 = 1 << 28;

const ETH_FCC_RX: u32 = 1 << 29;
const ETH_FCC_TX: u32 = 1 << 30;

const DMA_DESC_CR_TXEOF: u32 = 1 << 26;
const DMA_DESC_CR_TXSOF: u32 = 1 << 27;
const DMA_DESC_SR_ALL: u32 = 0xFC000000;

pub struct XilinxAxiEthernet {
    eth_base: IoMem<0x1000>,
    dma_base: IoMem<0x1000>,
    tx_desc: Box<[UnsafeCell<Descriptor>]>,
    rx_desc: Box<[UnsafeCell<Descriptor>]>,
    tx_used_ptr: usize,
    tx_avail_ptr: usize,
    rx_ptr: usize,
}

impl Drop for XilinxAxiEthernet {
    fn drop(&mut self) {
        self.stop();
    }
}

impl XilinxAxiEthernet {
    pub unsafe fn new(eth_base: usize, dma_base: usize, mac: [u8; 6]) -> Self {
        let tx_desc: Box<[UnsafeCell<Descriptor>]> = zeroed_slice(64);
        let rx_desc: Box<[UnsafeCell<Descriptor>]> = zeroed_slice(1024);

        for i in 0..tx_desc.len() {
            let tx_desc_next = &tx_desc[(i + 1) % tx_desc.len()];
            let desc = &mut *tx_desc[i].get();
            desc.next_desc = tx_desc_next.get();
            desc.buffer = Some(uninit_array::<_, 1514>());
            desc.buffer_address = desc.buffer.as_mut().unwrap().as_mut_ptr() as _;
            // Enable checksum offlaod
            desc.app[0] |= 2;
        }

        for i in 0..rx_desc.len() {
            let rx_desc_next = &rx_desc[(i + 1) % rx_desc.len()];
            let desc = &mut *rx_desc[i].get();
            desc.next_desc = rx_desc_next.get();
            desc.buffer = Some(uninit_array::<_, 1514>());
            desc.buffer_address = desc.buffer.as_mut().unwrap().as_mut_ptr() as _;
            desc.control = 1514;
        }

        let mut ret = XilinxAxiEthernet {
            eth_base: IoMem::new(eth_base),
            dma_base: IoMem::new(dma_base),
            tx_desc,
            rx_desc,
            tx_used_ptr: 0,
            tx_avail_ptr: 0,
            rx_ptr: 0,
        };

        ret.reset();
        ret.init(mac);

        let mut ctrl = ret.dma_base.read_u32(DMA_MM2S_DMACR_OFFSET);
        ctrl = (ctrl & !DMA_CR_COALESCE_MASK) | (1 << DMA_CR_COALESCE_SHIFT);
        ctrl = (ctrl & !DMA_CR_DELAY_MASK) | (0 << DMA_CR_DELAY_SHIFT);
        ctrl |= DMA_IRQ_ALL;
        ret.dma_base.write_u32(DMA_MM2S_DMACR_OFFSET, ctrl);

        let mut ctrl = ret.dma_base.read_u32(DMA_S2MM_DMACR_OFFSET);
        ctrl = (ctrl & !DMA_CR_COALESCE_MASK) | (1 << DMA_CR_COALESCE_SHIFT);
        ctrl = (ctrl & !DMA_CR_DELAY_MASK) | (0 << DMA_CR_DELAY_SHIFT);
        ctrl |= DMA_IRQ_ALL;
        ret.dma_base.write_u32(DMA_S2MM_DMACR_OFFSET, ctrl);

        // Set the current descriptor pointer to start of the ring
        ret.dma_base.write_u64(
            DMA_MM2S_CURDESC_OFFSET,
            ret.tx_desc.as_ptr() as usize as u64,
        );
        ret.dma_base.write_u64(
            DMA_S2MM_CURDESC_OFFSET,
            ret.rx_desc.as_ptr() as usize as u64,
        );

        // Run TX and RX DMA enigines.
        let ctrl = ret.dma_base.read_u32(DMA_MM2S_DMACR_OFFSET);
        ret.dma_base
            .write_u32(DMA_MM2S_DMACR_OFFSET, ctrl | DMA_CR_RUNSTOP);
        let ctrl = ret.dma_base.read_u32(DMA_S2MM_DMACR_OFFSET);
        ret.dma_base
            .write_u32(DMA_S2MM_DMACR_OFFSET, ctrl | DMA_CR_RUNSTOP);

        // Make RX engine ready for packets
        ret.dma_base.write_u64(
            DMA_S2MM_TAILDESC_OFFSET,
            ret.rx_desc[ret.rx_desc.len() - 1].get() as usize as u64,
        );

        ret
    }

    fn reset(&mut self) {
        info!("Reset DMA");
        // Set either MM2S_DMACR.Reset or S2MM.DMACR.Reset will reset the entire DMA engine (and ethernet).
        self.dma_base.write_u32(DMA_MM2S_DMACR_OFFSET, DMA_CR_RESET);
        // TODO: Timeout
        while self.dma_base.read_u32(DMA_MM2S_DMACR_OFFSET) & DMA_CR_RESET != 0 {
            // Sleep for a while maybe
        }
        info!("DMA resetted");
    }

    fn init(&mut self, mac: [u8; 6]) {
        // Disable RX and TX
        self.eth_base.write_u32(ETH_RCW1_OFFSET, 0);
        self.eth_base.write_u32(ETH_TC_OFFSET, 0);

        // Disable ETH interrupt
        self.eth_base.write_u32(ETH_IE_OFFSET, 0);

        // Enable flow control
        self.eth_base
            .write_u32(ETH_FCC_OFFSET, ETH_FCC_RX | ETH_FCC_TX);

        self.set_mac_address(mac);

        self.eth_base.write_u32(ETH_RCW1_OFFSET, ETH_RCW1_RX);
        self.eth_base.write_u32(ETH_TC_OFFSET, ETH_TC_TX);
    }

    fn stop(&mut self) {
        // Disable RX and TX
        self.eth_base.write_u32(ETH_RCW1_OFFSET, 0);
        self.eth_base.write_u32(ETH_TC_OFFSET, 0);

        let ctrl = self.dma_base.read_u32(DMA_MM2S_DMACR_OFFSET);
        self.dma_base.write_u32(
            DMA_MM2S_DMACR_OFFSET,
            ctrl & !(DMA_CR_RUNSTOP | DMA_IRQ_ALL),
        );

        let ctrl = self.dma_base.read_u32(DMA_S2MM_DMACR_OFFSET);
        self.dma_base.write_u32(
            DMA_S2MM_DMACR_OFFSET,
            ctrl & !(DMA_CR_RUNSTOP | DMA_IRQ_ALL),
        );

        for i in 0..=5 {
            if self.dma_base.read_u32(DMA_MM2S_DMASR_OFFSET) & DMA_SR_HALT != 0 {
                break;
            }
            if i != 5 {
                crate::timer::sleep(Duration::from_millis(20));
            } else {
                warn!(target: "xae", "cannot bring TX DMA to stop");
            }
        }
        for i in 0..=5 {
            if dbg!(self.dma_base.read_u32(DMA_S2MM_DMASR_OFFSET)) & DMA_SR_HALT != 0 {
                break;
            }
            if i != 5 {
                crate::timer::sleep(Duration::from_millis(20));
            } else {
                warn!(target: "xae", "cannot bring RX DMA to stop");
            }
        }

        self.reset();
    }

    fn set_mac_address(&mut self, mac: [u8; 6]) {
        self.eth_base.write_u32(
            ETH_UAW0_OFFSET,
            (mac[0] as u32) | (mac[1] as u32) << 8 | (mac[2] as u32) << 16 | (mac[3] as u32) << 24,
        );
        self.eth_base
            .write_u32(ETH_UAW1_OFFSET, (mac[4] as u32) | (mac[5] as u32) << 8);
    }
}

impl XilinxAxiEthernet {
    fn tokens(&mut self) -> (Option<TxToken>, Option<RxToken>) {
        if self.tx_avail_ptr >= self.tx_desc.len() {
            self.tx_avail_ptr -= self.tx_desc.len();
        }
        if self.rx_ptr >= self.rx_desc.len() {
            self.rx_ptr -= self.rx_desc.len();
        }

        let tx_desc = unsafe { &mut *self.tx_desc[self.tx_avail_ptr].get() };
        let tx_desc = if tx_desc.status & DMA_DESC_SR_ALL != 0 {
            None
        } else {
            Some(TxToken {
                dma_base: self.dma_base,
                desc: tx_desc,
                tx_ptr: &mut self.tx_avail_ptr,
            })
        };

        let rx_desc = unsafe { &mut *self.rx_desc[self.rx_ptr].get() };
        let rx_desc = if rx_desc.status & DMA_DESC_SR_ALL == 0 {
            None
        } else {
            Some(RxToken {
                dma_base: self.dma_base,
                desc: rx_desc,
                rx_ptr: &mut self.rx_ptr,
            })
        };

        (tx_desc, rx_desc)
    }

    pub fn handle_tx_irq(&mut self) {
        let status = self.dma_base.read_u32(DMA_MM2S_DMASR_OFFSET);

        // Bogus IRQ
        if status & DMA_IRQ_ALL == 0 {
            return;
        }

        // Clear IRQ bits
        self.dma_base.write_u32(DMA_MM2S_DMASR_OFFSET, status);

        if status & (DMA_IRQ_IOC | DMA_IRQ_DELAY) != 0 {
            loop {
                let desc = unsafe { &mut *self.tx_desc[self.tx_used_ptr].get() };
                if desc.status & DMA_DESC_SR_ALL == 0 {
                    break;
                }
                desc.status = 0;
                self.tx_used_ptr = if self.tx_used_ptr == self.tx_desc.len() - 1 {
                    0
                } else {
                    self.tx_used_ptr + 1
                };
            }
        }

        if status & DMA_IRQ_ERROR != 0 {
            unimplemented!("DMA error, ref axienet_tx_irq");
        }
    }

    pub fn handle_rx_irq(&mut self) {
        let status = self.dma_base.read_u32(DMA_S2MM_DMASR_OFFSET);

        // Bogus IRQ
        if status & DMA_IRQ_ALL == 0 {
            return;
        }

        // Clear IRQ bits
        self.dma_base.write_u32(DMA_S2MM_DMASR_OFFSET, status);

        if status & (DMA_IRQ_IOC | DMA_IRQ_DELAY) != 0 {}

        if status & DMA_IRQ_ERROR != 0 {
            unimplemented!("DMA error, ref axienet_rx_irq");
        }
    }
}

pub struct RxToken<'a> {
    dma_base: IoMem<0x1000>,
    desc: &'a mut Descriptor,
    rx_ptr: &'a mut usize,
}

pub struct TxToken<'a> {
    dma_base: IoMem<0x1000>,
    desc: &'a mut Descriptor,
    tx_ptr: &'a mut usize,
}

impl<'a> phy::Device<'a> for XilinxAxiEthernet {
    type RxToken = RxToken<'a>;
    type TxToken = TxToken<'a>;

    fn receive(&'a mut self) -> Option<(Self::RxToken, Self::TxToken)> {
        let (tx, rx) = self.tokens();
        rx.zip(tx)
    }

    fn transmit(&'a mut self) -> Option<Self::TxToken> {
        let (tx, _) = self.tokens();
        Some(tx.unwrap())
    }

    fn capabilities(&self) -> DeviceCapabilities {
        let mut cap = DeviceCapabilities::default();
        cap.max_transmission_unit = 1514;
        // TODO increase this
        cap.max_burst_size = Some(64);
        cap.checksum.ipv4 = Checksum::None;
        cap.checksum.udp = Checksum::None;
        cap.checksum.tcp = Checksum::None;
        cap
    }
}

impl<'a> phy::RxToken for RxToken<'a> {
    fn consume<R, F>(mut self, _timestamp: Instant, f: F) -> Result<R>
    where
        F: FnOnce(&mut [u8]) -> Result<R>,
    {
        let length = (self.desc.app[4] & 0x0000FFFF) as usize;
        let checksum_status = (self.desc.app[2] >> 3) & 0b111;
        if checksum_status & 0b100 != 0 {
            return Err(Error::Checksum);
        }

        let buf = unsafe { slice::from_raw_parts_mut(self.desc.buffer_address, length) };
        let result = f(buf);

        // Cleanup the descriptor and add it back to the RX available ring
        self.desc.status = 0;
        self.dma_base.write_u64(
            DMA_S2MM_TAILDESC_OFFSET,
            self.desc as *mut Descriptor as usize as u64,
        );
        *self.rx_ptr += 1;

        result
    }
}

impl<'a> phy::TxToken for TxToken<'a> {
    fn consume<R, F>(self, _timestamp: Instant, length: usize, f: F) -> Result<R>
    where
        F: FnOnce(&mut [u8]) -> Result<R>,
    {
        assert!(length <= 1514);
        let buf = unsafe { slice::from_raw_parts_mut(self.desc.buffer_address, length) };
        let result = f(buf);

        // Prepare the descriptor and send out
        self.desc.control = length as u32 | DMA_DESC_CR_TXSOF | DMA_DESC_CR_TXEOF;
        self.dma_base.write_u64(
            DMA_MM2S_TAILDESC_OFFSET,
            self.desc as *mut Descriptor as usize as u64,
        );
        *self.tx_ptr += 1;

        result
    }
}
