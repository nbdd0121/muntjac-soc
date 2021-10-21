#![allow(dead_code)]

use crate::block::Block;
use crate::io::{Read, Result};
use alloc::sync::Arc;
use byteorder::{ByteOrder, LE};

enum FatEntry {
    Free,
    Next(u32),
    Bad,
    End,
}

pub struct File<'a> {
    fs: &'a FileSystem,

    /// Current cluster to work on
    cluster: u32,

    /// Current sector to work on
    sector: u32,

    /// Buffer for non-sector sized read
    buf: [u8; 512],

    /// Pointer to available data within the buffer.
    /// * If buffer is not empty, this value should be within range [0, 512)
    /// * Value of 512 indicates that the buffer is empty.
    pointer: usize,

    /// Number of bytes left
    size: usize,
}

impl<'a> File<'a> {
    fn new(fs: &'a FileSystem, cluster: u32, size: usize) -> Self {
        File {
            fs,
            cluster,
            sector: 0,
            buf: [0; 512],
            pointer: 512,
            size,
        }
    }

    pub fn size(&self) -> u64 {
        self.size as u64
    }
}

impl Read for File<'_> {
    fn read(&mut self, mut buf: &mut [u8]) -> Result<usize> {
        // Make sure size is the cap.
        if buf.len() > self.size {
            buf = &mut buf[..self.size];
        }

        // Early return for a read of size zero.
        if buf.len() == 0 {
            return Ok(0);
        }

        // We have data left in the buffer.
        if self.pointer != 512 {
            let size = buf.len().min(512 - self.pointer);
            buf[..size].copy_from_slice(&self.buf[self.pointer..self.pointer + size]);
            self.pointer += size;
            self.size -= size;
            return Ok(size);
        }

        // We have reached the last cluster already (EOF).
        if self.cluster == 0 {
            return Ok(0);
        }

        // Compute the sector to use.
        let sector = self.fs.first_data_sector
            + (self.cluster - 2) * self.fs.sectors_per_cluster
            + self.sector;

        let sectors_to_read = (self.fs.sectors_per_cluster - self.sector)
            .min((buf.len() / 512) as u32)
            .max(1);

        // Advance cluster and sector information.
        self.sector += sectors_to_read;
        if self.sector == self.fs.sectors_per_cluster {
            match self.fs.read_fat_entry(self.cluster)? {
                FatEntry::Next(v) => {
                    self.cluster = v;
                    self.sector = 0;
                }
                FatEntry::End => {
                    self.cluster = 0;
                }
                _ => panic!("unexpected fat entry"),
            }
        }

        // Read full sectors
        if buf.len() >= 512 {
            let total_size = sectors_to_read as usize * 512;
            self.fs
                .block
                .read_exact_at(&mut buf[..total_size], sector as u64 * 512)?;
            self.size -= total_size;
            return Ok(total_size);
        }

        // Less than a sector.
        self.fs
            .block
            .read_exact_at(&mut self.buf, sector as u64 * 512)?;
        buf.copy_from_slice(&self.buf[..buf.len()]);
        self.pointer = buf.len();
        self.size -= buf.len();
        return Ok(buf.len());
    }
}

pub struct Dir<'a> {
    chain: File<'a>,
}

impl<'a> Iterator for Dir<'a> {
    type Item = Result<DirEntry<'a>>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.chain.size() < 32 {
            return None;
        }

        let mut lfn = [0; 256];
        let mut entry = [0; 32];
        loop {
            match self.chain.read_exact(&mut entry) {
                Ok(_) => (),
                Err(err) => return Some(Err(err)),
            }

            if entry[0] == 0 {
                return None;
            }

            if entry[0] == 0xE5 {
                // Unused entry
                continue;
            }

            if entry[11] == 0x0F {
                let mut index = ((entry[0] & 0x3f) - 1) as usize * 13;

                // Long file name
                for i in (1..11).step_by(2) {
                    let char = LE::read_u16(&entry[i..]);
                    lfn[index] = char;
                    index += 1;
                }
                for i in (14..26).step_by(2) {
                    let char = LE::read_u16(&entry[i..]);
                    lfn[index] = char;
                    index += 1;
                }
                for i in (28..32).step_by(2) {
                    let char = LE::read_u16(&entry[i..]);
                    lfn[index] = char;
                    index += 1;
                }

                continue;
            }

            // Volume ID
            if entry[11] & 0x08 != 0 {
                continue;
            }

            let mut filename = arrayvec::ArrayString::<[u8; 768]>::new();

            if lfn[0] == 0 {
                let lowercase = entry[12] & 0x08 != 0;
                for i in 0..8 {
                    let c: char = entry[i].into();
                    if c == ' ' {
                        continue;
                    }
                    filename.push(if lowercase { c.to_ascii_lowercase() } else { c });
                }

                // Only add dot it we have an extension
                if entry[8] != b' ' {
                    filename.push('.');
                }

                let lowercase = entry[12] & 0x10 != 0;
                for i in 8..11 {
                    let c: char = entry[i].into();
                    if c == ' ' {
                        continue;
                    }
                    filename.push(if lowercase { c.to_ascii_lowercase() } else { c });
                }
            } else {
                core::char::decode_utf16(lfn.iter().copied().take_while(|&x| x != 0))
                    .map(|r| r.unwrap_or(core::char::REPLACEMENT_CHARACTER))
                    .for_each(|c| filename.push(c));
            }

            let cluster =
                (LE::read_u16(&entry[20..]) as u32) << 16 | LE::read_u16(&entry[26..]) as u32;
            let file_size = LE::read_u32(&entry[28..]);

            return Some(Ok(DirEntry {
                fs: self.chain.fs,
                name: filename,
                cluster,
                size: file_size as usize,
                dir: entry[11] & 0x10 != 0,
            }));
        }
    }
}

pub struct DirEntry<'a> {
    fs: &'a FileSystem,
    name: arrayvec::ArrayString<[u8; 768]>,
    cluster: u32,
    size: usize,
    dir: bool,
}

impl<'a> DirEntry<'a> {
    pub fn file_name(&self) -> &str {
        &self.name
    }

    pub fn is_file(&self) -> bool {
        !self.dir
    }

    pub fn is_dir(&self) -> bool {
        self.dir
    }

    pub fn size(&self) -> u64 {
        assert!(!self.dir);
        self.size as u64
    }

    pub fn open(&self) -> File<'a> {
        assert!(!self.dir);
        File::new(self.fs, self.cluster, self.size)
    }

    pub fn readdir(&self) -> Dir<'a> {
        assert!(self.dir);
        Dir {
            chain: File::new(self.fs, self.cluster, core::usize::MAX),
        }
    }
}

pub struct FileSystem {
    block: Arc<dyn Block>,
    sectors_per_cluster: u32,
    reserved_sector_count: u32,
    first_data_sector: u32,
    root_cluster: u32,

    cache: spin::Mutex<(u32, [u8; 512])>,
}

impl FileSystem {
    fn read_fat_entry(&self, cluster: u32) -> Result<FatEntry> {
        let fat_offset = cluster * 4;
        let mut guard = self.cache.lock();

        if guard.0 == 0 || guard.0 / 512 != fat_offset / 512 {
            // Read the FAT into cache
            let fat_sector = self.reserved_sector_count + fat_offset / 512;
            self.block
                .read_exact_at(&mut guard.1, fat_sector as u64 * 512)?;
            guard.0 = fat_offset;
        }

        // We can use the cached FAT
        Ok(match LE::read_u32(&guard.1[fat_offset as usize % 512..]) {
            0 => FatEntry::Free,
            0x0FFFFFF7 => FatEntry::Bad,
            0x0FFFFFF8..=0x0FFFFFFF => FatEntry::End,
            v => FatEntry::Next(v),
        })
    }

    pub fn root(&self) -> Dir<'_> {
        Dir {
            chain: File::new(self, self.root_cluster, core::usize::MAX),
        }
    }
}

impl FileSystem {
    pub fn new(block: Arc<dyn Block>) -> Result<FileSystem> {
        let mut buf = [0; 512];

        // Read the BPB
        block.read_exact_at(&mut buf, 0)?;

        // Verify it's FAT32, not FAT12/16
        let fat_size = LE::read_u16(&buf[0x16..]);
        assert_eq!(fat_size, 0, "Only FAT32 is supported");

        assert_eq!(LE::read_u16(&buf[0x0B..]), 512, "FAT sector size not 512");
        let cluster_size = buf[0x0D] as u64 * 512;
        println!("FAT cluster size is {}", cluster_size);

        let reserved_sector_count = LE::read_u16(&buf[0x0E..]) as u32;
        let fat_count = buf[0x10] as u32;
        let fat_size = LE::read_u32(&buf[0x24..]);
        let first_data_sector = reserved_sector_count + fat_count * fat_size;

        println!("First data sector is at {}", first_data_sector);

        let root_cluster = LE::read_u32(&buf[0x2C..]);
        println!("Root directory is located at cluster {}", root_cluster);

        Ok(FileSystem {
            block,
            reserved_sector_count,
            sectors_per_cluster: buf[0x0D] as u32,
            first_data_sector,
            root_cluster,
            cache: spin::Mutex::new((0, [0; 512])),
        })
    }
}
