use rand::RngCore;
use std::env;
use std::fs;
use std::io::Result as IoResult;
use std::process::Command;
use std::str::FromStr;
use std::fmt::Write;

include!("platform.rs");

const MEMORY_LIMIT: u64 = MEMORY_BASE + MEMORY_SIZE;

fn main() -> IoResult<()> {
    let out_dir = env::var("OUT_DIR").unwrap();

    println!("cargo:rerun-if-changed=mac_address");
    let mac_address = match fs::read_to_string("mac_address") {
        Ok(v) => macaddr::MacAddr6::from_str(v.trim()).unwrap(),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            // Generate a MAC address if none is specified.
            let mut mac = [0u8; 6];
            let mut rng = rand::thread_rng();
            rng.fill_bytes(&mut mac);
            mac[0] = (mac[0] & 0xFE) | 0x02;

            let mac = macaddr::MacAddr6::from(mac);
            fs::write("mac_address", format!("{}\n", mac)).unwrap();
            mac
        }
        Err(err) => {
            panic!("Failed to read MAC address: {}", err);
        }
    };
    fs::write(
        format!("{}/mac_address.rs", out_dir),
        format!(
            "const MAC_ADDRESS: [u8; 6] = {:?};",
            mac_address.into_array()
        ),
    )
    .unwrap();
    let mut mac_address_for_dt = "[".to_string();
    for (i, byte) in mac_address.into_array().into_iter().enumerate() {
        if i != 0 {
            mac_address_for_dt.push(' ');
        }
        write!(mac_address_for_dt, "{:02x}", byte).unwrap();
    }
    mac_address_for_dt.push(']');

    // Load platform configuration
    println!("cargo:rerun-if-changed=platform.rs");

    // Generate for assembly use
    let platform_h = format!(
        "#define MEMORY_BASE {:#x}
#define MEMORY_LIMIT {:#x}",
        MEMORY_BASE, MEMORY_LIMIT,
    );
    fs::write(format!("{}/platform.h", out_dir), platform_h).unwrap();

    // Generate the linker script
    println!("cargo:rerun-if-changed=linker.tpl.ld");
    let tpl = fs::read_to_string("linker.tpl.ld").unwrap();
    let ld = tpl.replace("${MEMORY_LIMIT}", &format!("{:#x}", MEMORY_LIMIT));
    fs::write("linker.ld", ld).unwrap();

    println!("cargo:rerun-if-changed=device_tree.tpl.dts");
    let tpl = fs::read_to_string("device_tree.tpl.dts").unwrap();
    let dts = tpl
        .replace("${MEMORY_BASE}", &format!("{:x}", MEMORY_BASE))
        .replace("${MEMORY_SIZE}", &format!("{:x}", MEMORY_SIZE - 0x200000))
        .replace("${MAC_ADDRESS}", &mac_address_for_dt);
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
