use std::env;
use std::fs;
use std::io::Result as IoResult;
use std::process::Command;

include!("platform.rs");

const MEMORY_LIMIT: u64 = MEMORY_BASE + MEMORY_SIZE;

fn main() -> IoResult<()> {
    let out_dir = env::var("OUT_DIR").unwrap();

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
        .replace("${MEMORY_SIZE}", &format!("{:x}", MEMORY_SIZE - 0x200000));
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
