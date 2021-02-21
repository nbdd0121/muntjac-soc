pub fn mdio_read(addr: u8, reg: u8) -> u16 {
    unsafe {
    core::ptr::write_volatile(0x1004_07E4 as *mut u32, 0b1_00000_00000 | (addr as u32) << 5 | reg as u32);
    // Enable MDIO interface
    core::ptr::write_volatile(0x1004_07F0 as *mut u32, 0b1_00_0);
    // Initiate MDIO
    core::ptr::write_volatile(0x1004_07F0 as *mut u32, 0b1_00_1);
    // Wait for MDIO to complete
    while core::ptr::read_volatile(0x1004_07F0 as *mut u32) & 1 != 0 {}
    // Retrieve the value
    core::ptr::read_volatile(0x1004_07EC as *mut u32) as u16
    }
}

struct Xemaclite {
    base: usize,
}

impl Xemaclite {
    fn set_mac_address(&mut self, mac: [u8; 6]) {
        let w0 = u32::from_le_bytes([mac[0], mac[1], mac[2], mac[3]]);
        let w1 = u16::from_le_bytes([mac[4], mac[5]]) as u32;
        unsafe {
            // Put both addresses into the transmit buffer
            core::ptr::write_volatile((self.base + 0x0) as *mut u32, w0);
            core::ptr::write_volatile((self.base + 0x4) as *mut u32, w1);

            // Set both send and program bit to set MAC address
            core::ptr::write_volatile((self.base + 0x7FC) as *mut u32, 3);
            
            // Wait until status bit to turn low
            while core::ptr::read_volatile((self.base + 0x7FC) as *mut u32) & 1 != 0 {}
        }
    }
}

pub fn ethernet_init() {
    println!("Mac address setting");
    Xemaclite { base: 0x1004_0000 }.set_mac_address([0x00, 0x00, 0x5E, 0x00, 0xFA, 0xCE]);
    println!("Mac address set");
    println!("PHY ID = {}:{}", mdio_read(1, 2), mdio_read(1, 3));
    let mut buffer = [0; 1520];
    {
        while !recv(&mut buffer, false) {}
        dbg!(&buffer[6..12]);
        while !recv(&mut buffer, true) {}
        dbg!(&buffer[6..12]);
    }
}

pub fn recv(packet: &mut [u8], pong: bool) -> bool {
    let addr_offset = if pong { 0x1800 } else { 0x1000 };
    unsafe {
        let status = core::ptr::read_volatile((0x1004_0000 + addr_offset + 0x7FC) as *mut u32);
        if status & 1 != 0 {
            for i in 0..380 {
                packet[i*4..i*4+4].copy_from_slice(&core::ptr::read_volatile((0x1004_0000 + addr_offset + i * 4) as *mut u32).to_le_bytes());
            }
            core::ptr::write_volatile((0x1004_0000 + addr_offset + 0x7FC) as *mut u32, status &! 1);
            true
        } else {
            false
        }
    }
}
