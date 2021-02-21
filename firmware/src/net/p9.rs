use super::tcp::{self, Shutdown, TcpStream};
use alloc::vec::Vec;
use byteorder::{ByteOrder, LE};
use core::num::Wrapping;
use core::str;
use core::time::Duration;
use smoltcp::wire::IpEndpoint;

#[derive(Debug)]
pub enum Error {
    Io(smoltcp::Error),
    Malformed,
    P9(u32),
}

pub type Result<T> = core::result::Result<T, Error>;

impl From<smoltcp::Error> for Error {
    fn from(err: smoltcp::Error) -> Self {
        Error::Io(err)
    }
}

struct P9Helper<'a> {
    stream: TcpStream,
    tag: Wrapping<u16>,
    buf: &'a mut [u8],
    ptr: usize,
    max_count: usize,
}

#[derive(Debug)]
struct Stat {
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub nlink: u64,
    pub rdev: u64,
    pub size: u64,
    pub blksize: u64,
    pub blocks: u64,
    pub atime: Duration,
    pub mtime: Duration,
    pub ctime: Duration,
}

#[derive(Debug)]
pub struct Qid {
    pub r#type: u8,
    pub version: u32,
    pub path: u64,
}

impl<'a> P9Helper<'a> {
    fn start_pkt(&mut self, msg: u8) {
        self.ptr = 4;
        self.write_u8(msg);
        self.ptr += 2;
    }

    fn write_u8(&mut self, val: u8) {
        self.buf[self.ptr] = val;
        self.ptr += 1;
    }

    fn write_u16(&mut self, val: u16) {
        LE::write_u16(&mut self.buf[self.ptr..], val);
        self.ptr += 2;
    }

    fn write_u32(&mut self, val: u32) {
        LE::write_u32(&mut self.buf[self.ptr..], val);
        self.ptr += 4;
    }

    fn write_u64(&mut self, val: u64) {
        LE::write_u64(&mut self.buf[self.ptr..], val);
        self.ptr += 8;
    }

    fn write_str(&mut self, val: &str) {
        self.write_u16(val.len() as u16);
        self.buf[self.ptr..self.ptr + val.len()].copy_from_slice(val.as_bytes());
        self.ptr += val.len();
    }

    fn read_u8(&mut self) -> u8 {
        let ret = self.buf[self.ptr];
        self.ptr += 1;
        ret
    }

    fn read_u16(&mut self) -> u16 {
        let ret = LE::read_u16(&mut self.buf[self.ptr..]);
        self.ptr += 2;
        ret
    }

    fn read_u32(&mut self) -> u32 {
        let ret = LE::read_u32(&mut self.buf[self.ptr..]);
        self.ptr += 4;
        ret
    }

    fn read_u64(&mut self) -> u64 {
        let ret = LE::read_u64(&mut self.buf[self.ptr..]);
        self.ptr += 8;
        ret
    }

    fn read_str(&mut self) -> &str {
        let len = self.read_u16() as usize;
        let ret = str::from_utf8(&self.buf[self.ptr..self.ptr + len]).unwrap();
        self.ptr += len;
        ret
    }

    fn read_qid(&mut self) -> Qid {
        Qid {
            r#type: self.read_u8(),
            version: self.read_u32(),
            path: self.read_u64(),
        }
    }

    fn read_time(&mut self) -> Duration {
        Duration::new(self.read_u64(), self.read_u64() as u32)
    }

    fn read_stat(&mut self) -> Stat {
        let stat = Stat {
            mode: self.read_u32(),
            uid: self.read_u32(),
            gid: self.read_u32(),
            nlink: self.read_u64(),
            rdev: self.read_u64(),
            size: self.read_u64(),
            blksize: self.read_u64(),
            blocks: self.read_u64(),
            atime: self.read_time(),
            mtime: self.read_time(),
            ctime: self.read_time(),
        };
        let _ = self.read_time();
        let _ = self.read_u64();
        let _ = self.read_u64();
        stat
    }

    async fn send_req(&mut self, msg: u8) -> Result<()> {
        LE::write_u32(&mut self.buf[0..], self.ptr as u32);
        self.buf[4] = msg;
        LE::write_u16(&mut self.buf[5..], self.tag.0);
        self.stream.write_all(&self.buf[..self.ptr]).await?;
        self.tag += Wrapping(1);
        Ok(())
    }

    async fn recv(&mut self, msg: u8) -> Result<()> {
        // Read the header
        self.stream.read_exact(&mut self.buf[..7]).await?;
        self.ptr = 0;
        let length = self.read_u32() as usize;
        let rxmsg = self.read_u8();
        let _ = self.read_u16();

        self.stream.read_exact(&mut self.buf[7..length]).await?;

        if rxmsg != msg {
            if rxmsg == 7 {
                return Err(Error::P9(self.read_u32()));
            }
            return Err(Error::Malformed);
        }
        Ok(())
    }

    async fn send_version(&mut self) -> Result<()> {
        self.tag = Wrapping(65535);
        self.start_pkt(100);
        self.write_u32(65536);
        self.write_str("9P2000.L");
        self.send_req(100).await?;
        self.tag = Wrapping(1);
        Ok(())
    }

    async fn recv_version(&mut self) -> Result<()> {
        self.recv(101).await?;
        let msize = self.read_u32();
        let _version = self.read_str();
        self.max_count = (msize as usize).min(65536) - 24;
        Ok(())
    }

    async fn send_attach(&mut self, fid: u32) -> Result<()> {
        self.start_pkt(104);
        self.write_u32(fid);
        self.write_u32(u32::MAX);
        self.write_str("root");
        self.write_str("/mnt/d/Scratchpad/9p");
        self.write_u32(u32::MAX);
        self.send_req(104).await?;
        Ok(())
    }

    async fn recv_attach(&mut self) -> Result<()> {
        self.recv(105).await?;
        // Ignore the QID
        Ok(())
    }

    async fn send_walk(&mut self, fid: u32, newfid: u32, names: &[&str]) -> Result<()> {
        self.start_pkt(110);
        self.write_u32(fid);
        self.write_u32(newfid);
        self.write_u16(names.len() as u16);
        for name in names {
            self.write_str(name);
        }
        self.send_req(110).await?;
        Ok(())
    }

    async fn recv_walk(&mut self) -> Result<()> {
        self.recv(111).await?;
        // Ignore the QID
        Ok(())
    }

    async fn send_open(&mut self, fid: u32, flags: u32) -> Result<()> {
        self.start_pkt(12);
        self.write_u32(fid);
        self.write_u32(flags);
        self.send_req(12).await?;
        Ok(())
    }

    async fn recv_open(&mut self) -> Result<()> {
        self.recv(13).await?;
        // Ignore the QID and iounit
        Ok(())
    }

    async fn send_read(&mut self, fid: u32, offset: u64, count: u32) -> Result<()> {
        self.start_pkt(116);
        self.write_u32(fid);
        self.write_u64(offset);
        self.write_u32(count);
        self.send_req(116).await?;
        Ok(())
    }

    async fn recv_read(&mut self, buf: &mut [u8]) -> Result<usize> {
        // Read the header + 4 bytes
        self.stream.read_exact(&mut self.buf[..11]).await?;
        self.ptr = 0;
        let length = self.read_u32() as usize;
        let rxmsg = self.read_u8();
        let _ = self.read_u16();
        if rxmsg != 117 {
            if rxmsg == 7 {
                return Err(Error::P9(self.read_u32()));
            }
            return Err(Error::Malformed);
        }

        let count = self.read_u32() as usize;
        if length != 11 + count {
            return Err(Error::Malformed);
        }

        self.stream.read_exact(&mut buf[..count]).await?;
        Ok(count)
    }

    async fn send_clunk(&mut self, fid: u32) -> Result<()> {
        self.start_pkt(120);
        self.write_u32(fid);
        self.send_req(120).await?;
        Ok(())
    }

    async fn recv_clunk(&mut self) -> Result<()> {
        self.recv(121).await?;
        Ok(())
    }

    async fn send_getattr(&mut self, fid: u32, request_mask: u64) -> Result<()> {
        self.start_pkt(24);
        self.write_u32(fid);
        self.write_u64(request_mask);
        self.send_req(24).await?;
        Ok(())
    }

    async fn recv_getattr(&mut self) -> Result<Stat> {
        self.recv(25).await?;
        let _ = self.read_u64();
        let _ = self.read_qid();
        Ok(self.read_stat())
    }
}

async fn do_read_file<'a>(remote: IpEndpoint, path: &str) -> Result<Vec<u8>> {
    let stream = TcpStream::new();
    for port in 49152..(49152 + 16) {
        match stream.connect(remote, port).await {
            Ok(_) => break,
            Err(tcp::Error::Unaddressable) if port != 49152 + 15 => (),
            Err(err) => Err(err)?,
        }
    }

    let mut buf = [0; 512];
    let mut helper = P9Helper {
        stream,
        tag: Wrapping(0),
        buf: &mut buf,
        ptr: 0,
        max_count: 0,
    };
    helper.send_version().await?;
    helper.recv_version().await?;
    helper.send_attach(0).await?;
    helper.recv_attach().await?;
    helper.send_walk(0, 1, &[path]).await?;
    helper.recv_walk().await?;
    helper.send_open(1, 0).await?;
    helper.recv_open().await?;
    helper.send_getattr(1, 0x200).await?;
    let size = helper.recv_getattr().await?.size as usize;
    info!("File size is {}", size);

    let mut data = Vec::with_capacity(size);
    unsafe { data.set_len(size) };

    let mut offset = 0;
    while offset < size {
        let max_count = (size - offset).min(helper.max_count);
        helper.send_read(1, offset as u64, max_count as u32).await?;
        let bytes = helper.recv_read(&mut data[offset..]).await?;
        offset += bytes;
    }
    info!("loaded");
    helper.send_clunk(1).await?;
    helper.recv_clunk().await?;
    helper.send_clunk(0).await?;
    helper.recv_clunk().await?;
    helper.stream.shutdown(Shutdown::Both).await?;
    Ok(data)
}

#[allow(dead_code)]
pub async fn read_file<'a, T: Into<IpEndpoint>>(remote: T, path: &str) -> Result<Vec<u8>> {
    do_read_file(remote.into(), path).await
}
