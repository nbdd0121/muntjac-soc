pub mod p9;
pub mod tcp;
pub mod xae;

use alloc::vec::Vec;
use smoltcp::socket::{SocketSet, SocketSetItem};
use spin::Mutex;

static mut SOCKET_STORAGE: [Option<SocketSetItem>; 8] =
    [None, None, None, None, None, None, None, None];
static SOCKETS: Mutex<Option<SocketSet>> = Mutex::new(None);

pub fn with_sockets<R>(f: impl FnOnce(&mut SocketSet<'static>) -> R) -> R {
    let mut guard = SOCKETS.lock();
    if guard.is_none() {
        *guard = Some(SocketSet::new(unsafe { &mut SOCKET_STORAGE[..] }))
    }
    f(guard.as_mut().unwrap())
}

pub fn load_kernel() -> Vec<u8> {
    use alloc::collections::BTreeMap;
    use core::future::Future;
    use core::pin::Pin;
    use core::task::{Context, Poll};

    use smoltcp::iface::{EthernetInterfaceBuilder, NeighborCache, Routes};
    use smoltcp::time::Instant;
    use smoltcp::wire::{EthernetAddress, IpAddress, IpCidr, Ipv4Address};

    use xae::XilinxAxiEthernet;

    let mac = [0x02, 0x00, 0x00, 0x00, 0x00, 0x01];

    let device = unsafe { XilinxAxiEthernet::new(0x10100000, 0x10200000, mac) };

    let neighbor_cache = NeighborCache::new(BTreeMap::new());

    let ethernet_addr = EthernetAddress(mac);
    let mut ip_addrs = [IpCidr::new(IpAddress::v4(10, 5, 1, 128), 24)];

    let default_v4_gw = Ipv4Address::new(10, 5, 1, 1);
    let mut routes_storage = [None; 2];
    let mut routes = Routes::new(&mut routes_storage[..]);
    routes.add_default_ipv4_route(default_v4_gw).unwrap();

    let mut iface = EthernetInterfaceBuilder::new(device)
        .ethernet_addr(ethernet_addr)
        .neighbor_cache(neighbor_cache)
        .ip_addrs(&mut ip_addrs[..])
        .routes(routes)
        .finalize();

    let mut client = async {
        let remote = IpAddress::v4(10, 5, 1, 2);
        p9::read_file((remote, 564), "vmlinux").await.unwrap()
    };

    loop {
        let timestamp = Instant::from_millis((crate::timer::time_u64() / 1000) as i64);
        match with_sockets(|sockets| iface.poll(sockets, timestamp)) {
            Ok(_) => {}
            Err(e) => {
                debug!("poll error: {}", e);
            }
        }

        fn clone(_: *const ()) -> core::task::RawWaker {
            core::task::RawWaker::new(core::ptr::null(), &VTABLE)
        }
        static VTABLE: core::task::RawWakerVTable =
            core::task::RawWakerVTable::new(clone, |_| (), |_| (), |_| ());

        let waker = unsafe {
            core::task::Waker::from_raw(core::task::RawWaker::new(core::ptr::null(), &VTABLE))
        };
        let mut cx = Context::from_waker(&waker);

        let poll = Future::poll(unsafe { Pin::new_unchecked(&mut client) }, &mut cx);

        match poll {
            Poll::Ready(data) => return data,
            Poll::Pending => (),
        }

        iface.device_mut().handle_tx_irq();
        iface.device_mut().handle_rx_irq();
    }
}
