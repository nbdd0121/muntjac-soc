#![allow(dead_code)]
#[allow(unused)]
mod sys {
    pub const INCOMPAT_FILETYPE: u32 = 0x2;
    pub const INCOMPAT_RECOVER: u32 = 0x4;
    pub const INCOMPAT_EXTENTS: u32 = 0x40;
    pub const INCOMPAT_64BIT: u32 = 0x80;
    pub const INCOMPAT_FLEX_BG: u32 = 0x200;

    pub const EXT4_EXTENTS_FL: u32 = 0x80000;

    #[repr(C)]
    pub struct SuperBlock {
        pub inodes_count: u32,
        pub blocks_count_lo: u32,
        pub r_blocks_count_lo: u32,
        pub free_blocks_count_lo: u32,
        pub free_inodes_count: u32,
        pub first_data_block: u32,
        pub log_block_size: u32,
        pub log_frag_size: u32,
        pub blocks_per_group: u32,
        pub frags_per_group: u32,
        pub inodes_per_group: u32,
        pub mtime: u32,
        pub wtime: u32,

        pub mnt_count: u16,
        pub max_mnt_count: u16,
        pub magic: u16,
        pub state: u16,
        pub errors: u16,
        pub minor_rev_level: u16,
        pub lastcheck: u32,
        pub checkinterval: u32,
        pub creator_os: u32,
        pub rev_level: u32,
        pub def_resuid: u16,
        pub def_resgid: u16,

        pub first_ino: u32,
        pub inode_size: u16,
        pub block_group_nr: u16,
        pub feature_compat: u32,
        pub feature_incompat: u32,
        pub feature_ro_compat: u32,
        pub uuid: [u8; 16],
        pub volume_name: [u8; 16],
        pub last_mounted: [u8; 64],
        pub algorithm_usage_bitmap: u32,

        pub prealloc_blocks: u8,
        pub prealloc_dir_blocks: u8,
        pub reserved_gdt_blocks: u16,

        pub journal_uuid: [u8; 16],
        pub journal_inum: u32,
        pub journal_dev: u32,
        pub last_orphan: u32,
        pub hash_seed: [u32; 4],
        pub def_hash_version: u8,
        pub jnl_backup_type: u8,
        pub desc_size: u8,
        pub default_mount_opts: u32,
        pub first_meta_bg: u32,
        pub mkfs_time: u32,
        pub jnl_blocks: [u32; 17],
        // TODO: More
    }

    #[derive(Debug, Clone, Copy)]
    #[repr(C)]
    pub struct Inode {
        pub mode: u16,
        pub uid: u16,
        pub size_lo: u32,
        pub atime: u32,
        pub ctime: u32,
        pub mtime: u32,
        pub dtime: u32,
        pub gid: u16,
        pub links_count: u16,
        pub blocks_count_lo: u32,
        pub flags: u32,
        pub osd1: u32,
        pub blocks: [u32; 15],
        pub generation: u32,
        pub file_acl_lo: u32,
        pub size_high: u32,
        pub obso_faddr: u32,
        pub osd2: [u8; 12],
        pub extra_isize: u16,
        pub checksum_hi: u16,
        pub ctime_extra: u32,
        pub mtime_extra: u32,
        pub atime_extra: u32,
        pub crtime: u32,
        pub crtime_extra: u32,
        pub version_hi: u32,
        pub projid: u32,
    }

    #[derive(Debug)]
    #[repr(C)]
    pub struct ExtentHeader {
        pub magic: u16,
        pub entries: u16,
        pub max: u16,
        pub depth: u16,
        pub generation: u32,
    }

    #[derive(Debug, Clone, Copy)]
    #[repr(C)]
    pub struct ExtentIdx {
        pub block: u32,
        pub leaf_lo: u32,
        pub leaf_hi: u16,
        pub unused: u16,
    }

    #[derive(Debug, Clone, Copy)]
    #[repr(C)]
    pub struct Extent {
        pub block: u32,
        pub len: u16,
        pub start_hi: u16,
        pub start_lo: u32,
    }

    #[derive(Debug)]
    #[repr(C)]
    pub struct GroupDesc {
        pub block_bitmap_lo: u32,
        pub inode_bitmap_lo: u32,
        pub inode_table_lo: u32,
        pub free_blocks_count_lo: u16,
        pub free_inodes_count_lo: u16,
        pub used_dirs_count_lo: u16,
        pub flags: u16,
        pub exclude_bitmap_lo: u32,
        pub block_bitmap_csum_lo: u16,
        pub inode_bitmap_csum_lo: u16,
        pub itable_unused_lo: u16,
        pub checksum: u16,
        pub block_bitmap_hi: u32,
        pub inode_bitmap_hi: u32,
        pub inode_table_hi: u32,
        pub free_blocks_count_hi: u16,
        pub free_inodes_count_hi: u16,
        pub used_dirs_count_hi: u16,
        pub itable_unused_hi: u16,
        pub exclude_bitmap_hi: u32,
        pub block_bitmap_csum_hi: u16,
        pub inode_bitmap_csum_hi: u16,
        pub reserved: u32,
    }

    #[derive(Debug)]
    #[repr(C)]
    pub struct DirEntryRaw {
        pub inode: u32,
        pub rec_len: u16,
        pub name_len: u8,
        pub file_type: u8,
        pub name: [u8; 255],
    }
}

use crate::io::{Error, Result as IoResult, Read, ReadAt};
use crate::util::OnceCell;
use crate::{block::Block, util::uninit_slice};
use alloc::boxed::Box;
use alloc::sync::Arc;
use core::mem;
use spin::Mutex;
use sys::*;

const INCOMPAT_SUPPORTED: u32 = 0x2C6;

pub struct File<'a> {
    fs: &'a FileSystem,
    ino: u32,
    inode: Inode,

    ptr: u64,
}

impl<'a> File<'a> {
    fn new(fs: &'a FileSystem, ino: u32, inode: Inode) -> Self {
        File {
            fs,
            ino,
            inode,
            ptr: 0,
        }
    }

    pub fn size(&self) -> u64 {
        (self.inode.size_high as u64) << 32 | self.inode.size_lo as u64
    }
}

impl ReadAt for File<'_> {
    fn read_at(&mut self, mut buf: &mut [u8], offset: u64) -> IoResult<usize> {
        let limit = offset + buf.len() as u64;

        // Cap the buf size within limit.
        if limit > self.size() {
            buf = &mut buf[..(self.size() - offset) as usize];
        }

        // Early return for a read of size zero.
        if buf.len() == 0 {
            return Ok(0);
        }

        self.fs
            .read_inode(self.ino, &self.inode, &mut buf, offset)?;

        return Ok(buf.len());
    }
}

impl Read for File<'_> {
    fn read(&mut self, buf: &mut [u8]) -> IoResult<usize> {
        let size = self.read_at(buf, self.ptr)?;
        self.ptr += size as u64;
        Ok(size)
    }
}

pub struct Dir<'a> {
    file: File<'a>,
}

impl<'a> Iterator for Dir<'a> {
    type Item = IoResult<DirEntry<'a>>;

    fn next(&mut self) -> Option<Self::Item> {
        loop {
            let mut dir: DirEntryRaw = unsafe { mem::zeroed() };

            // Read into the DirEntry
            let buf_view = unsafe {
                core::slice::from_raw_parts_mut(
                    &mut dir as *mut _ as *mut u8,
                    mem::size_of::<DirEntryRaw>(),
                )
            };
            match self.file.read_at(buf_view, self.file.ptr) {
                Err(err) => return Some(Err(err)),
                Ok(0) => return None,
                Ok(1..=7) => return Some(Err(Error::Textual("Unexpected short dir entry"))),
                _ => (),
            };

            self.file.ptr += dir.rec_len as u64;

            if dir.inode == 0 {
                continue;
            }

            // Check if the entry is UTF-8. If not, skip it.
            // TODO: Maybe replace?
            match core::str::from_utf8(&dir.name[..dir.name_len as usize]) {
                // Skip . and .. for consistency with other FS implemented
                Ok(".") | Ok("..") => continue,
                Err(_) => continue,
                _ => (),
            }

            return Some(Ok(DirEntry {
                fs: self.file.fs,
                raw: dir,
                inode: OnceCell::new(),
            }));
        }
    }
}

pub struct DirEntry<'a> {
    fs: &'a FileSystem,
    raw: DirEntryRaw,
    inode: OnceCell<Inode>,
}

impl<'a> DirEntry<'a> {
    pub fn file_name(&self) -> &str {
        unsafe { core::str::from_utf8_unchecked(&self.raw.name[..self.raw.name_len as usize]) }
    }

    pub fn is_file(&self) -> bool {
        self.raw.file_type == 1
    }

    pub fn is_dir(&self) -> bool {
        self.raw.file_type == 2
    }

    fn fetch_inode(&self) -> IoResult<&Inode> {
        self.inode
            .get_or_try_init(|| self.fs.get_inode(self.raw.inode))
    }

    pub fn size(&self) -> IoResult<u64> {
        assert!(self.is_file());
        let inode = self.fetch_inode()?;
        Ok((inode.size_high as u64) << 32 | inode.size_lo as u64)
    }

    pub fn open(&self) -> IoResult<File<'a>> {
        assert!(self.is_file());
        let inode = self.fetch_inode()?;
        Ok(File::new(self.fs, self.raw.inode, *inode))
    }

    pub fn readdir(&self) -> IoResult<Dir<'a>> {
        assert!(self.is_file());
        let inode = self.fetch_inode()?;
        Ok(Dir {
            file: File::new(self.fs, self.raw.inode, *inode),
        })
    }
}

pub struct FileSystem {
    block: Arc<dyn Block>,
    superblock: SuperBlock,

    group_desc_cache: Mutex<(u64, Box<[u8]>)>,
    extent_cache: Mutex<(u32, Box<[u32]>)>,
    cache: Mutex<(u64, Box<[u8]>)>,
}

impl FileSystem {
    pub fn new(block: Arc<dyn Block>) -> IoResult<Self> {
        let mut buf = [0; 1024];

        // Read the super block
        block.read_exact_at(&mut buf, 1024)?;
        let mut superblock: SuperBlock = unsafe { mem::transmute_copy(&buf[0]) };

        if superblock.magic != 0xEF53 {
            return Err(Error::Textual("Not a EXT filesystem"));
        }

        if superblock.rev_level == 0 {
            superblock.feature_incompat = 0;
        }

        if superblock.feature_incompat & !INCOMPAT_SUPPORTED != 0 {
            return Err(Error::Textual(
                "Filesystem contains unsupported incompatible features",
            ));
        }

        if superblock.feature_incompat & INCOMPAT_64BIT == 0 {
            // Fake desc_size if 64-bit flag is not set
            superblock.desc_size = 32;
        }

        let block_size = 1024 << superblock.log_block_size;

        let fs = FileSystem {
            block,
            superblock,
            group_desc_cache: spin::Mutex::new((0, unsafe { uninit_slice(block_size) })),
            extent_cache: spin::Mutex::new((0, unsafe { uninit_slice(block_size / 4) })),
            cache: spin::Mutex::new((0, unsafe { uninit_slice(block_size) })),
        };

        Ok(fs)
    }

    fn read_block(&self, buf: &mut [u8], block: u64) -> IoResult<()> {
        let block_shift = self.superblock.log_block_size + 10;
        debug_assert_eq!(buf.len() & ((1 << block_shift) - 1), 0);
        self.block.read_exact_at(buf, block << block_shift)
    }

    fn read_with_cache(
        &self,
        cache: &mut (u64, Box<[u8]>),
        mut buf: &mut [u8],
        mut offset: u64,
    ) -> IoResult<()> {
        let block_shift = self.superblock.log_block_size + 10;
        let block_size = 1 << block_shift;
        let block_mask = block_size as u64 - 1;

        // First read to align offset to block
        if offset & block_mask != 0 {
            let blk = offset >> block_shift;
            let blk_offset = (offset & block_mask) as usize;

            if cache.0 != blk {
                cache.0 = blk;
                self.block.read_exact_at(&mut cache.1, blk << block_shift)?;
            }

            if buf.len() <= block_size - blk_offset {
                buf.copy_from_slice(&cache.1[blk_offset..][..buf.len()]);
                return Ok(());
            } else {
                let copy_len = block_size - blk_offset;
                buf[..copy_len].copy_from_slice(&cache.1[blk_offset..]);
                buf = &mut buf[copy_len..];
                offset += copy_len as u64;
            }
        }

        debug_assert!(offset & block_mask == 0);

        let (full_buf, partial_buf) = buf.split_at_mut(buf.len() & !(block_mask as usize));
        if !full_buf.is_empty() {
            self.block.read_exact_at(full_buf, offset)?;
            offset += full_buf.len() as u64;
        }

        if !partial_buf.is_empty() {
            if cache.0 != offset >> block_shift {
                cache.0 = offset >> block_shift;
                self.block.read_exact_at(&mut cache.1, offset)?;
            }
            partial_buf.copy_from_slice(&cache.1[..partial_buf.len()]);
        }

        Ok(())
    }

    fn read(&self, buf: &mut [u8], offset: u64) -> IoResult<()> {
        let mut cache = self.cache.lock();
        self.read_with_cache(&mut cache, buf, offset)
    }

    fn get_group_desc(&self, group: u32) -> IoResult<GroupDesc> {
        // Group descriptor is located immediately after superblock.
        let group_desc_idx = if self.superblock.log_block_size == 0 {
            2
        } else {
            1
        };

        let desc_offset = (group_desc_idx << (self.superblock.log_block_size + 10))
            + group as u64 * self.superblock.desc_size as u64;
        let mut buf = [0; mem::size_of::<GroupDesc>()];

        let mut cache = self.group_desc_cache.lock();
        self.read_with_cache(
            &mut cache,
            &mut buf[..self.superblock.desc_size as usize],
            desc_offset,
        )
        .unwrap();
        // This is safe and will produce sensible GroupDesc because we pre-init buf to zero,
        // so any unfilled fields are all zeroed out.
        let desc: GroupDesc = unsafe { mem::transmute_copy(&buf) };

        Ok(desc)
    }

    fn get_inode(&self, inode: u32) -> IoResult<Inode> {
        let inode_group_index = (inode - 1) / self.superblock.inodes_per_group;
        let inode_group_offset = (inode - 1) % self.superblock.inodes_per_group;

        let desc = self.get_group_desc(inode_group_index)?;

        let mut buf = [0; mem::size_of::<Inode>()];
        let ino_offset = ((desc.inode_table_lo as u64 | (desc.inode_table_hi as u64) << 32)
            << (self.superblock.log_block_size + 10))
            + inode_group_offset as u64 * self.superblock.inode_size as u64;
        self.read(
            &mut buf[..mem::size_of::<Inode>().min(self.superblock.inode_size as usize)],
            ino_offset,
        )
        .unwrap();
        let ino: Inode = unsafe { mem::transmute_copy(&buf) };

        Ok(ino)
    }

    fn get_extent_leaf<'a>(
        &self,
        ino: u32,
        cache: &mut (u32, Box<[u32]>),
        extent: &'a [u32],
        block: u32,
    ) -> IoResult<Option<Extent>> {
        // Ensure some of the invariants are held.
        assert_eq!(mem::size_of::<ExtentHeader>(), 12);
        assert_eq!(mem::size_of::<ExtentIdx>(), 12);
        assert_eq!(mem::size_of::<Extent>(), 12);

        #[repr(C)]
        pub struct ExtentNode<T> {
            pub header: ExtentHeader,
            pub nodes: [T],
        }

        enum ExtentType<'a> {
            Invalid,
            Branch(&'a ExtentNode<ExtentIdx>),
            Leaf(&'a ExtentNode<Extent>),
        }

        fn parse_node(arr: &[u32]) -> ExtentType<'_> {
            let num_nodes = mem::size_of_val(arr) / 12;
            assert!(num_nodes >= 1);

            #[repr(C)]
            struct FatPtr<T> {
                data: *const T,
                len: usize,
            }

            let header = unsafe { &*(arr.as_ptr() as *const ExtentHeader) };

            if header.magic != 0xF30A {
                return ExtentType::Invalid;
            }

            if header.entries as usize >= num_nodes {
                return ExtentType::Invalid;
            }

            if header.depth == 0 {
                ExtentType::Leaf(unsafe {
                    mem::transmute(FatPtr {
                        data: arr.as_ptr() as _,
                        len: header.entries as usize,
                    })
                })
            } else {
                ExtentType::Branch(unsafe {
                    mem::transmute(FatPtr {
                        data: arr.as_ptr() as _,
                        len: header.entries as usize,
                    })
                })
            }
        }

        fn search_leaf(nodes: &ExtentNode<Extent>, block: u32) -> Option<Extent> {
            let extent_idx = match nodes.nodes.binary_search_by_key(&block, |node| node.block) {
                Ok(v) => v,
                Err(0) => return None,
                Err(v) => v - 1,
            };

            let node = &nodes.nodes[extent_idx];

            let blk_within_extent = block - node.block;
            if blk_within_extent >= node.len as u32 {
                return None;
            }

            return Some(*node);
        }

        fn search_branch(nodes: &ExtentNode<ExtentIdx>, block: u32) -> Option<ExtentIdx> {
            let extent_idx = match nodes.nodes.binary_search_by_key(&block, |node| node.block) {
                Ok(v) => v,
                Err(0) => return None,
                Err(v) => v - 1,
            };

            let node = &nodes.nodes[extent_idx];
            return Some(*node);
        }

        // If the buffer contains leaf nodes of this inode, use the result as the cache
        if cache.0 == ino {
            match parse_node(&cache.1) {
                ExtentType::Leaf(nodes) => {
                    return Ok(search_leaf(nodes, block));
                }
                _ => (),
            }
        }

        let mut cur_extent = extent;
        loop {
            match parse_node(cur_extent) {
                ExtentType::Invalid => {
                    return Err(Error::Textual("Invalid entent magic"));
                }
                ExtentType::Leaf(nodes) => {
                    return Ok(search_leaf(nodes, block));
                }
                ExtentType::Branch(nodes) => {
                    let node = search_branch(nodes, block)
                        .ok_or_else(|| Error::Textual("Cannot find extent"))?;
                    let block = (node.leaf_hi as u64) << 32 | node.leaf_lo as u64;

                    // SAFETY: This make a [u8] view of [u32].
                    let buffer_view = unsafe {
                        core::slice::from_raw_parts_mut(
                            cache.1.as_mut_ptr() as *mut u8,
                            cache.1.len() * 4,
                        )
                    };
                    cache.0 = 0;
                    self.read_block(buffer_view, block)?;
                    cache.0 = ino;
                    cur_extent = &cache.1;
                }
            };
        }
    }

    fn read_inode(
        &self,
        ino: u32,
        inode: &Inode,
        mut buf: &mut [u8],
        mut offset: u64,
    ) -> IoResult<()> {
        let shift = self.superblock.log_block_size + 10;
        while !buf.is_empty() {
            let blk = (offset >> shift) as u32;
            let blk_offset = offset - ((blk as u64) << shift);

            let (blk_idx, nr_blk) = if inode.flags & EXT4_EXTENTS_FL != 0 {
                let mut cache = self.extent_cache.lock();
                let node = self
                    .get_extent_leaf(ino, &mut cache, &inode.blocks, blk)?
                    .unwrap();

                let block = (node.start_hi as u64) << 32 | node.start_lo as u64;
                let blk_within_extent = blk - node.block;
                (
                    block + blk_within_extent as u64,
                    node.len as usize - blk_within_extent as usize,
                )
            } else {
                todo!("direct {}", blk);
            };

            let len = buf.len().min((nr_blk << shift) - blk_offset as usize);
            self.read(&mut buf[..len], (blk_idx << shift) + blk_offset)?;
            buf = &mut buf[len..];
            offset += len as u64;
        }
        Ok(())
    }
}

impl FileSystem {
    pub fn root(&self) -> IoResult<Dir<'_>> {
        let ino = self.get_inode(2)?;
        Ok(Dir {
            file: File::new(self, 2, ino),
        })
    }
}
