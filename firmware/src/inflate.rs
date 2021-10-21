use crate::io::{Error, Result};
use alloc::vec::Vec;
use byteorder::{ByteOrder, LE};

bitflags::bitflags! {
    struct Flags: u8 {
        const TEXT = 1 << 0;
        const HCRC = 1 << 1;
        const EXTRA = 1 << 2;
        const NAME = 1 << 3;
        const COMMENT = 1 << 4;
    }
}

pub fn is_gzip(file: &[u8]) -> bool {
    file.len() > 18 && file[0] == 0x1f && file[1] == 0x8b
}

pub fn inflate(gzip: &[u8]) -> Result<Vec<u8>> {
    if gzip[0] != 0x1f || gzip[1] != 0x8b {
        return Err(Error::Textual("not gzip"));
    }
    if gzip[2] != 8 {
        return Err(Error::Textual("not deflate"));
    }

    let mut ptr = 10;
    let flags = Flags::from_bits_truncate(gzip[3]);
    if flags.contains(Flags::EXTRA) {
        let xlen = LE::read_u16(&gzip[ptr..]);
        ptr += xlen as usize;
    }
    if flags.contains(Flags::NAME) {
        let nul_pos = gzip[ptr..].iter().position(|&b| b == 0).unwrap();
        ptr += nul_pos + 1;
    }
    if flags.contains(Flags::COMMENT) {
        let nul_pos = gzip[ptr..].iter().position(|&b| b == 0).unwrap();
        ptr += nul_pos + 1;
    }
    if flags.contains(Flags::HCRC) {
        ptr += 2;
    }

    let inflated = miniz_oxide::inflate::decompress_to_vec(&gzip[ptr..gzip.len() - 8])
        .map_err(|_| Error::Textual("inflate failed"))?;

    let tail = &gzip[gzip.len() - 8..];
    let crc = LE::read_u32(tail);
    let size = LE::read_u32(&tail[4..]);

    let mut hasher = crc32fast::Hasher::new();
    hasher.update(&inflated);
    if hasher.finalize() != crc {
        return Err(Error::Textual("CRC check failed"));
    }

    if inflated.len() != size as usize {
        return Err(Error::Textual("size check failed"));
    }

    Ok(inflated)
}
