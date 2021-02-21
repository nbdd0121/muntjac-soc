#[derive(Debug)]
pub enum Error {
    Textual(&'static str),
}

pub type Result<T> = core::result::Result<T, Error>;
