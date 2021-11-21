use rand::RngCore;
use regex::{Captures, Regex};
use std::borrow::Cow;
use std::env;
use std::fs;
use std::io::Result as IoResult;
use std::process::Command;

fn main() -> IoResult<()> {
    let out_dir = env::var("OUT_DIR").unwrap();

    // Read device tree source file.
    // Device tree is the canonical source of truth for all the info.
    let dts_file = env::var("DTS").unwrap();
    let mut dts = fs::read_to_string(&dts_file)?;

    // Extract mac address from device tree source file
    let mac_re =
        Regex::new(r"(mac-address\s*=\s*\[)\s*(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)")
            .unwrap();
    let mut mac_addr = [0u8; 6];
    let mut need_replace = false;
    dts = match mac_re.replace(&dts, |caps: &Captures| {
        for i in 0..6 {
            mac_addr[i] = u8::from_str_radix(&caps[i + 2], 16).unwrap();
        }

        // Generate a MAC address if the existing one is of all zeros.
        if mac_addr.into_iter().max().unwrap() == 0 {
            need_replace = true;

            let mut rng = rand::thread_rng();
            rng.fill_bytes(&mut mac_addr);
            mac_addr[0] = (mac_addr[0] & 0xFE) | 0x02;
        }

        format!(
            "{}{:02x} {:02x} {:02x} {:02x} {:02x} {:02x}",
            &caps[1], mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4], mac_addr[5]
        )
    }) {
        Cow::Owned(s) => s,
        _ => panic!("cannot find mac address in device tree"),
    };

    if need_replace {
        fs::write(dts_file, &dts)?;
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

    fs::write(
        format!("{}/mac_address.rs", out_dir),
        format!("const MAC_ADDRESS: [u8; 6] = {:?};", mac_addr),
    )
    .unwrap();

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

    fs::write("device_tree.dts", dts).unwrap();
    let dtb = format!("{}/device_tree.dtb", out_dir);
    let status = Command::new("dtc")
        .args(&["device_tree.dts", "-o", &dtb])
        .status()
        .expect("failed to execute fdt");
    assert!(status.success());

    let mut cc = cc::Build::new();
    println!("cargo:rerun-if-changed=src/entry.S");
    cc.file("src/entry.S");
    cc.include(out_dir).compile("foo");

    Ok(())
}
