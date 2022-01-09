use rand::RngCore;
use regex::{Captures, Regex};
use std::borrow::Cow;
use std::env;
use std::fmt::Write;
use std::fs;
use std::process::Command;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out_dir = env::var("OUT_DIR").unwrap();

    println!("cargo:rerun-if-changed=../build/linker");

    // Read device tree source file.
    // Device tree is the canonical source of truth for all the info.
    let master_dts_file = env::var("DTS").unwrap();
    let mut dts = fs::read_to_string(&master_dts_file)?;
    let dts_file = "device_tree.dts";
    let dtb_file = format!("{}/device_tree.dtb", out_dir);
    println!("cargo:rerun-if-changed={}", master_dts_file);

    // Compile master device tree source into binary and load it.
    let status = Command::new("dtc")
        .args(&[&master_dts_file, "-o", &dtb_file])
        .status()
        .expect("failed to execute fdt");
    assert!(status.success());
    let fdt = fs::read(&dtb_file)?;
    let fdt = fdt::Fdt::new(&fdt).unwrap();

    // Extract mac address from device tree source file
    let mac_re =
        Regex::new(r"(mac-address\s*=\s*\[)\s*(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)")
            .unwrap();
    let mut mac_addr = None;
    let mut need_replace = false;
    dts = mac_re
        .replace(&dts, |caps: &Captures| {
            let mut mac = [0u8; 6];
            for i in 0..6 {
                mac[i] = u8::from_str_radix(&caps[i + 2], 16).unwrap();
            }

            // Generate a MAC address if the existing one is of all zeros.
            if mac.into_iter().max().unwrap() == 0 {
                need_replace = true;

                let mut rng = rand::thread_rng();
                rng.fill_bytes(&mut mac);
                mac[0] = (mac[0] & 0xFE) | 0x02;
            }

            mac_addr = Some(mac);

            format!(
                "{}{:02x} {:02x} {:02x} {:02x} {:02x} {:02x}",
                &caps[1], mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
            )
        })
        .into_owned();

    if need_replace {
        fs::write(master_dts_file, &dts)?;
    }

    // Extract memory size from device tree source file
    let memory_re =
        Regex::new(r"(memory@\w+\s*\{\s*reg\s*=\s*/bits/\s*64\s*<)\s*0x(\w+)\s*0x(\w+)").unwrap();
    let mut memory_base = 0;
    let mut memory_size = 0;
    dts = match memory_re.replace(&dts, |caps: &Captures| {
        memory_base = u64::from_str_radix(&caps[2], 16).unwrap();
        memory_size = u64::from_str_radix(&caps[3], 16).unwrap();

        // Reserve 2MB for the firmware.
        format!(
            "{}{:#010x} {:#010x}",
            &caps[1],
            memory_base,
            memory_size - 0x200000
        )
    }) {
        Cow::Owned(s) => s,
        _ => panic!("cannot find memory block in device tree"),
    };
    let memory_limit = memory_base + memory_size;

    // Find the address of CLINT and remove that node.
    let clint_base;
    {
        let node = fdt
            .find_compatible(&["sifive,clint0"])
            .expect("cannot find CLINT node");
        let reg = node.raw_reg().unwrap().next().unwrap();
        clint_base = u64::from_be_bytes(reg.address.try_into()?);

        let re = Regex::new(&format!(r"{}\s*\{{[^}}]*\}}\s*;\s*", node.name)).unwrap();
        dts = re.replace(&dts, "").into_owned();
    };

    // Compile modified device tree source into binary.
    fs::write(&dts_file, dts)?;
    let status = Command::new("dtc")
        .args(&[&dts_file, "-o", &dtb_file])
        .status()
        .expect("failed to execute fdt");
    assert!(status.success());

    let mut generated_rs = String::new();

    let num_harts = fdt.cpus().count();
    writeln!(generated_rs, "pub const NUM_HARTS: usize = {};", num_harts)?;

    writeln!(
        generated_rs,
        "pub const MEMORY_BASE: usize = {:#x};",
        memory_base
    )?;
    writeln!(
        generated_rs,
        "pub const MEMORY_SIZE: usize = {:#x};",
        memory_size
    )?;
    writeln!(
        generated_rs,
        "pub const CLINT_BASE: usize = {:#x};",
        clint_base
    )?;

    // Extract UART address.
    if let Some(node) = fdt.find_compatible(&["ns16550a"]) {
        let reg = node.raw_reg().unwrap().next().unwrap();
        let base = u64::from_be_bytes(reg.address.try_into()?);
        let offset = node
            .property("reg-offset")
            .map(|p| u32::from_be_bytes(p.value.try_into().unwrap()))
            .unwrap_or(0);
        writeln!(
            generated_rs,
            "pub const UART_BASE: usize = {:#x};",
            base + offset as u64
        )?;
    }

    if let Some(node) = fdt.find_compatible(&["garyguo,sdhci"]) {
        let reg = node.raw_reg().unwrap().next().unwrap();
        let base = u64::from_be_bytes(reg.address.try_into()?);
        writeln!(generated_rs, "pub const SD_BASE: usize = {:#x};", base)?;
    }

    if let Some(node) = fdt.find_compatible(&["xlnx,axi-ethernet-1.00.a"]) {
        let mut regs = node.raw_reg().unwrap();
        let mac_base = u64::from_be_bytes(regs.next().unwrap().address.try_into()?);
        let dma_base = u64::from_be_bytes(regs.next().unwrap().address.try_into()?);
        writeln!(
            generated_rs,
            "pub const ETH_MAC_BASE: usize = {:#x};",
            mac_base
        )?;
        writeln!(
            generated_rs,
            "pub const ETH_DMA_BASE: usize = {:#x};",
            dma_base
        )?;
        writeln!(
            generated_rs,
            "pub const MAC_ADDRESS: [u8; 6] = {:?};",
            mac_addr.expect("Ethernet controller exists but not a mac address")
        )?;
    }

    fs::write(format!("{}/address.rs", out_dir), generated_rs)?;

    // Generate for assembly use
    let platform_h = format!(
        "#define MEMORY_BASE {:#x}
#define MEMORY_LIMIT {:#x}",
        memory_base, memory_limit,
    );
    fs::write(format!("{}/platform.h", out_dir), platform_h).unwrap();

    // Generate the linker script
    println!("cargo:rerun-if-changed=linker.tpl.ld");
    let tpl = fs::read_to_string("linker.tpl.ld").unwrap();
    let ld = tpl.replace("${MEMORY_LIMIT}", &format!("{:#x}", memory_limit));
    fs::write("linker.ld", ld).unwrap();

    let mut cc = cc::Build::new();
    println!("cargo:rerun-if-env-changed=CC");
    println!("cargo:rerun-if-env-changed=CFLAGS");
    println!("cargo:rerun-if-changed=src/entry.S");
    cc.file("src/entry.S");
    println!("cargo:rerun-if-changed=src/memcpy.S");
    cc.file("src/memcpy.S");
    println!("cargo:rerun-if-changed=src/memmove.S");
    cc.file("src/memmove.S");
    println!("cargo:rerun-if-changed=src/memset.S");
    cc.file("src/memset.S");
    cc.include(out_dir).compile("foo");

    Ok(())
}
