# NoqeriOS networking milestone: Ethernet + IPv4 boot bring-up

## Implemented in this change

- **VirtIO PCI network driver** for a modern `virtio-net-pci` adapter, PCI
  vendor `1af4`, device `1041` (modern VirtIO network).
- `VIRTIO_F_VERSION_1` and `VIRTIO_NET_F_MAC` negotiation; reads the MAC from
  the PCI device configuration capability. Unsupported devices fail safely.
- Bus-master DMA split virtqueues (RX queue 0, TX queue 1), with one bounded
  outstanding RX buffer and one synchronous TX buffer. Interrupts and
  multiqueue are **not** yet implemented.
- Ethernet framing, IPv4 header checksum, IPv4 UDP datagrams,
  DHCP Discover/Offer/Request/Ack for obtaining an IPv4 lease, netmask,
  router and DNS address, ARP lookup for gateway MAC, and an ICMP echo probe.
- Failure/no-network path exits on bounded polling and continues normal boot.
- QEMU virtual Ethernet test behind user-mode NAT with no inbound port forwarding; it confirms
  hardware-independent DMA operation, a **real DHCP response** from the
  virtual network, and gateway ARP exchange.

## Test

```sh
# Already-configured compiler, QEMU and Linux build environment:
NOQERIOS_NETWORK=1 bash Tests/qemu-smoke.sh
```

The test adds a **virtual** network device on QEMU user-mode NAT (no
forwarded inbound ports) and expects:
```
NoqeriOS: VirtIO Ethernet DMA RX/TX queues online
NoqeriOS: DHCP IPv4 lease acquired
NoqeriOS: IPv4 gateway ARP resolved (Ethernet connected)
```

The optional ICMP gateway echo is logged, but is not required as some host
network configurations cannot proxy ICMP echo. QEMU normally omits DHCP
router option 3 if `restrict=on`; therefore the gateway test uses regular
user-mode NAT, with **no inbound host forwarding**. The guest sends only
DHCP/ARP and a gateway ICMP probe and does not intentionally contact
arbitrary public internet hosts. Public network reachability is NOT tested.

## Boundaries: this is NOT a complete internet-capable OS yet

| Interface or protocol | Status |
|---|---|
| Modern VirtIO Ethernet on PCI | Driver implemented; QEMU regression required |
| Other physical Ethernet devices (Intel e1000/e1000e/igc, Realtek r8169) | Not implemented |
| USB Ethernet or Android USB tethering (CDC-ECM/NCM/RNDIS) | Not implemented |
| DHCPv4, IPv4, ARP, UDP, basic ICMP | Minimal bootstrap subset implemented |
| TCP streaming, retransmission, congestion control | Not implemented |
| DNS client, resolver, sockets, HTTP/HTTPS, TLS, certificates | Not implemented |
| IPv6/SLAAC, fragmentation, routing table/firewall | Not implemented |
| Wi-Fi hardware, 802.11 association and WPA2/WPA3 | Not implemented |
| Bluetooth HCI/L2CAP/PAN/BNEP tethering | Not implemented |
| Cellular modem (LTE/5G, MBIM/QMI, PPP) | Not implemented |
| DHCP renewal and always-on network service | Not implemented |
| Preemptive/interrupt-driven NIC ingress | Not implemented |

A phone's **Wi-Fi hotspot** is ordinary Wi-Fi at the client end (requiring a
Wi-Fi driver and security protocols). **USB tethering** is an Ethernet-like
USB networking adapter (requiring a USB host controller and CDC/RNDIS driver).
**Bluetooth tethering** needs Bluetooth PAN/BNEP. None are interchangeable
with a PCI VirtIO NIC.

## Subsequent implementation sequence

1. Stabilize the device abstraction: lifecycle, DMA ownership, queue recycling,
   IRQ/MSI-X, softirq receive loop, transmit buffer ownership, unplug support.
2. Add PCI physical Ethernet NIC families (e1000/e1000e first, then r8169),
   validated in QEMU and real hardware.
3. Build a persistent network manager with IPv4 configuration, timer-backed
   DHCP renew/rebind, ARP cache, UDP port demultiplexing, DNS, socket API.
4. Implement TCP with retransmission, timers, receive windows, flow and
   congestion control, then HTTP client and TLS with secure RNG and
   certificate verification. Only then claim practical internet access.
5. Implement xHCI/USB, USB Ethernet/tethering, 802.11 wireless driver and
   WPA supplicant, Bluetooth HCI/PAN/BNEP, cellular MBIM/QMI as distinct
   adapter/protocol projects.
6. Add packet fuzzing, malformed input tests, isolation and permission
   checks before exposing the kernel to untrusted external networks.

## Security considerations

The current parser has finite bounds but is **experimental and not hardened**.
Do not attach NoqeriOS to the open internet, public Wi-Fi, or a corporate LAN
while TCP/IP and driver isolation are incomplete. DHCP and ARP are inherently
untrusted; the boot probe does not implement lease refresh, ARP-spoofing
mitigation, firewall policy or sandboxing. Prefer the QEMU isolated test above.
