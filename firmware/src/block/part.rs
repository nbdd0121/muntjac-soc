use super::Block;
use crate::io::Result as IoResult;
use alloc::sync::Arc;

pub struct Part {
    blk: Arc<dyn Block>,
    offset: u64,
}

impl Part {
    pub fn new(blk: Arc<dyn Block>, offset: u64) -> Self {
        Self { blk, offset }
    }

    pub fn first_partition(blk: Arc<dyn Block>) -> IoResult<Self> {
        let mut buf = [0; 512];

        // Read the MBR
        blk.read_exact_at(&mut buf, 0)?;

        assert_eq!(buf[510], 0x55, "MBR not valid");
        assert_eq!(buf[511], 0xAA, "MBR not valid");

        // Check partition 1
        let part = &buf[0x1BE..0x1CE];
        assert_eq!(part[4], 0x0C, "Only FAT32 is supported");
        let mut lba = [0; 4];
        lba.copy_from_slice(&part[0x8..0xC]);
        let lba = u32::from_le_bytes(lba);
        let part_offset = lba as u64 * 512;

        println!("FAT32 partition located at {}KiB", lba / 2);
        Ok(Self::new(blk, part_offset))
    }
}

impl super::Block for Part {
    fn read_exact_at(&self, buf: &mut [u8], offset: u64) -> IoResult<()> {
        self.blk.read_exact_at(buf, offset + self.offset)
    }

    fn write_all_at(&self, buf: &[u8], offset: u64) -> IoResult<()> {
        self.blk.write_all_at(buf, offset + self.offset)
    }

    fn len(&self) -> u64 {
        todo!();
    }
}
