#[derive(Debug)]
pub enum Error {
    Textual(&'static str),
}

pub type Result<T> = core::result::Result<T, Error>;

pub trait Read {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize>;

    fn read_exact(&mut self, mut buf: &mut [u8]) -> Result<()> {
        while !buf.is_empty() {
            let size = self.read(buf)?;
            if size == 0 {
                return Err(Error::Textual("early eof"));
            }
            buf = &mut buf[size..];
        }
        Ok(())
    }
}

pub trait ReadAt {
    fn read_at(&mut self, buf: &mut [u8], offset: u64) -> Result<usize>;

    fn read_exact_at(&mut self, mut buf: &mut [u8], mut offset: u64) -> Result<()> {
        while !buf.is_empty() {
            let size = self.read_at(buf, offset)?;
            if size == 0 {
                return Err(Error::Textual("early eof"));
            }
            buf = &mut buf[size..];
            offset += size as u64;
        }
        Ok(())
    }
}
