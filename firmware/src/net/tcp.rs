use core::future::Future;
use core::pin::Pin;
use core::task::{Context, Poll};
use core::time::Duration;
use smoltcp::socket::{SocketHandle, SocketRef, TcpSocket, TcpSocketBuffer, TcpState};
use smoltcp::wire::IpEndpoint;

use super::with_sockets;

pub use smoltcp::{Error, Result};

#[derive(Debug, PartialEq, Eq)]
pub enum Shutdown {
    Write,
    Both,
}

pub struct TcpStream {
    handle: SocketHandle,
}

impl Drop for TcpStream {
    fn drop(&mut self) {
        with_sockets(|set| set.remove(self.handle));
    }
}

struct PollFut<'a, R, F>
where
    F: FnMut(&mut TcpSocket<'_>) -> Poll<R>,
{
    stream: &'a TcpStream,
    tx: bool,
    rx: bool,
    f: F,
}

impl<'a, R, F> Unpin for PollFut<'a, R, F> where F: FnMut(&mut TcpSocket<'_>) -> Poll<R> {}

impl<'a, R, F> Future for PollFut<'a, R, F>
where
    F: FnMut(&mut TcpSocket<'_>) -> Poll<R>,
{
    type Output = R;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<R> {
        self.stream.with_socket(|socket| {
            let ret = (self.f)(socket);
            if ret.is_pending() {
                if self.tx {
                    socket.register_send_waker(cx.waker());
                }
                if self.rx {
                    socket.register_recv_waker(cx.waker());
                }
            }
            ret
        })
    }
}

impl TcpStream {
    fn with_socket<R>(&self, f: impl FnOnce(&mut TcpSocket<'static>) -> R) -> R {
        with_sockets(|set| {
            let mut socket: SocketRef<TcpSocket> = set.get(self.handle);
            f(&mut socket)
        })
    }

    pub fn new() -> Self {
        // Ideally we want a connect to return TcpStream. We currrently cannot do this
        // because we don't have a proper allocator.
        let rx_buffer = TcpSocketBuffer::new(vec![0; 65536]);
        let tx_buffer = TcpSocketBuffer::new(vec![0; 65536]);
        let socket = TcpSocket::new(rx_buffer, tx_buffer);

        let handle = with_sockets(|set| set.add(socket));
        TcpStream { handle }
    }

    async fn do_connect(&self, remote: IpEndpoint, local_port: u16) -> Result<()> {
        info!(target: "tcp", "Connecting port {} to {}", local_port, remote);

        self.with_socket(|socket| {
            socket.abort();
            socket.connect(remote, local_port)
        })?;

        PollFut {
            stream: self,
            tx: true,
            rx: false,
            f: |socket| match socket.state() {
                TcpState::SynSent => Poll::Pending,
                TcpState::Closed => Poll::Ready(Err(Error::Unaddressable)),
                _ => Poll::Ready(Ok(())),
            },
        }
        .await?;

        info!(target: "tcp", "Connected port {} to {}", local_port, remote);
        Ok(())
    }

    #[allow(dead_code)]
    pub fn set_ack_delay(&self, duration: Option<Duration>) {
        self.with_socket(|socket| socket.set_ack_delay(duration.map(Into::into)));
    }

    pub async fn connect<T: Into<IpEndpoint>>(&self, remote: T, local_port: u16) -> Result<()> {
        self.do_connect(remote.into(), local_port).await
    }

    fn try_write(&self, buf: &[u8]) -> Result<usize> {
        self.with_socket(|socket| socket.send_slice(buf))
    }

    pub async fn writable(&self) -> Result<()> {
        PollFut {
            stream: self,
            tx: true,
            rx: false,
            f: |socket| {
                if socket.can_send() {
                    Poll::Ready(Ok(()))
                } else if socket.may_send() {
                    Poll::Pending
                } else {
                    Poll::Ready(Err(Error::Illegal))
                }
            },
        }
        .await
    }

    async fn write(&self, buf: &[u8]) -> Result<usize> {
        self.writable().await?;
        self.try_write(buf)
    }

    pub async fn write_all(&self, mut buf: &[u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.write(buf).await {
                Ok(0) => {
                    return Err(Error::Truncated);
                }
                Ok(n) => buf = &buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    pub async fn readable(&self) -> Result<()> {
        PollFut {
            stream: self,
            tx: false,
            rx: true,
            f: |socket| {
                if socket.can_recv() {
                    Poll::Ready(Ok(()))
                } else if socket.may_recv() {
                    Poll::Pending
                } else {
                    // This may also be FIN or illegal. Check by calling recv
                    match socket.recv(|_| (0, ())).unwrap_err() {
                        Error::Finished => Poll::Pending,
                        err => Poll::Ready(Err(err)),
                    }
                }
            },
        }
        .await
    }

    pub fn try_read_with<F, R>(&self, f: F) -> Result<R>
    where
        F: FnOnce(&[u8]) -> (usize, R),
    {
        let mut f = Some(f);
        with_sockets(|set| {
            let mut socket = set.get::<TcpSocket>(self.handle);
            match socket.recv(|buf| (f.take().unwrap())(buf)) {
                Err(Error::Finished) => Ok((f.take().unwrap())(&[]).1),
                ret => ret,
            }
        })
    }

    pub async fn read_with<F, R>(&self, f: F) -> Result<R>
    where
        F: FnOnce(&[u8]) -> (usize, R),
    {
        self.readable().await?;
        self.try_read_with(f)
    }

    pub async fn read(&self, buf: &mut [u8]) -> Result<usize> {
        self.read_with(|data| {
            let len = buf.len().min(data.len());
            buf[..len].copy_from_slice(&data[..len]);
            (len, len)
        })
        .await
    }

    pub async fn read_exact(&self, mut buf: &mut [u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.read(buf).await {
                Ok(0) => {
                    return Err(Error::Truncated);
                }
                Ok(n) => buf = &mut buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    pub async fn shutdown(&self, how: Shutdown) -> Result<()> {
        self.with_socket(|socket| socket.close());
        PollFut {
            stream: self,
            tx: true,
            rx: false,
            f: |socket| match socket.state() {
                TcpState::FinWait2 if how == Shutdown::Write => Poll::Ready(Ok(())),
                TcpState::TimeWait | TcpState::Closed => Poll::Ready(Ok(())),
                _ => Poll::Pending,
            },
        }
        .await
    }
}
