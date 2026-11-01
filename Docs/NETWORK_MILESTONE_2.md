# NoqeriOS networking milestone 2

## Scope and test status

This change extends the merged VirtIO DHCP/IPv4 foundation with physical-NIC
families and an initial name-resolution client. It is **not** a complete
internet-capable kernel and is **not** safe to put on an untrusted network.
CI QEMU emulation is necessary but does not certify a particular physical
motherboard, PHY, EEPROM, IOMMU, DMA implementation, or cable/link state.

| Layer / adapter | Targeted capability | Remaining limitations |
|---|---|---|
| Modern VirtIO PCI Ethernet | Existing isolated QEMU DHCP and gateway ARP | Polling, one RX/TX descriptor; no IRQ/NAPI |
| Intel 82540EM `8086:100e` | PCI BAR1 I/O registers, EEPROM MAC fallback, RX/TX DMA | Exact 82540EM only, hardware validation pending |
| Realtek RTL8139 `10ec:8139` | PCI PIO and legacy RX ring, four TX slots | Old RTL8139 only; **not** RTL8169/RTL8111 |
| IPv4, DHCP, UDP, ARP, ICMP | Shared packet path for each adapter; idle cooperative ARP/ICMP replies | No DHCP lease refresh, ARP cache, fragmentation, IPv6 or sockets |
| DNS | Fixed `example.com` A-record query with bounded reply parsing, response tuple checks, deterministic parser fixture | Not a general caching resolver, DNSSEC, or DNS-over-TLS |
| TCP | Not implemented | Reliable streams require per-connection state, retransmissions, congestion/flow control |
| HTTPS | Not implemented | Requires mature TCP, cryptographic primitives, TLS 1.3, trusted clocks and certificate validation |
| USB Ethernet / phone USB tether | Not implemented | xHCI + CDC ECM/NCM/RNDIS/MBIM host drivers |
| Wi-Fi and phone Wi-Fi hotspot | Not implemented | Chipset driver, 802.11 scan/association, key management, WPA2/WPA3 |
| Bluetooth PAN / phone BT hotspot | Not implemented | Host-controller HCI, L2CAP, SDP and BNEP |
| Cellular LTE/5G | Not implemented | USB/PCIe modem, QMI/MBIM/AT, SIM control and bearer setup |

## Build and integration tests

With Linux, QEMU and the Noqeri compiler set up:

```sh
NOQERIOS_NETWORK=virtio bash Tests/qemu-smoke.sh
NOQERIOS_NETWORK=e1000 bash Tests/qemu-smoke.sh
NOQERIOS_NETWORK=rtl8139 bash Tests/qemu-smoke.sh
```

Tests must witness real DMA transmit/receive, DHCP OFFER/ACK, and ARP
responses from QEMU's NAT gateway. All three adapters share the same
packet encoder/decoder. Offline boot and UEFI tests also run in CI.

Interactive COM1 commands: `n` reports the IPv4 lease, `g` probes the
configured gateway, and `d` makes one best-effort IPv4 A lookup of
`example.com`. DNS lookups may fail when no upstream resolver is
available; a deterministic offline parser fixture is independent of DNS
availability.

The basic network event pump operates only while the serial shell is idle:
it replies to IPv4 ARP and ICMP echo requests, not to TCP connections.
Because no timed DHCP renewal or general packet queue exists yet, do not
interpret this as a production network manager.

## Next dependency-ordered work

1. Stabilize a real NIC/PHY abstraction with DMA ownership and IOMMU,
   correct memory caching, device reset/unplug, MSI-X/IRQ and asynchronous
   receive queues. Add hardware testing across specific device revisions.
2. Add DHCP lease lifetimes, renew/rebind state and monotonic timers,
   subnet-aware routing/ARP cache, UDP sockets, ICMP validation, DNS APIs.
3. Implement a TCP socket state machine and test SYN, ACK, FIN, RST, MSS,
   windows, retransmissions, out-of-order delivery, congestion control,
   timeout handling, fuzzing and half-open connection limits.
4. Build a robust cryptographic CSPRNG and TLS 1.3 with authenticated
   cipher suites, X.509 chain and hostname validation, revocation policy
   and secure clock handling before HTTPS.
5. Implement xHCI USB and individual CDC-ECM/NCM/RNDIS/MBIM drivers,
   802.11/WPA2-WPA3 with chipset firmware licensing, Bluetooth HCI/PAN,
   and cellular modem state machines. Each requires device matrix tests.

Never write network credentials into firmware logs, GitHub Actions output
or plaintext kernel logs. Wi-Fi/Bluetooth/modem support cannot be
implemented by substituting a different Ethernet PCI vendor ID.
