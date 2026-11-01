# NoqeriOS TCP protocol milestone — local end-to-end fixture

## Added

`Kernel/net/tcp.noqeri` is the first native Noqeri TCP active-open implementation
on the existing IPv4/Ethernet stack. It constructs TCP and IPv4 packets, adds
the IPv4 pseudo-header checksum, checks incoming IPv4/TCP frame lengths,
remote IPv4 and port tuple, TCP checksum, sequence/acknowledgement, and
the SYN/SYN-ACK/ACK handshake. It then issues a small HTTP/1.0 GET.

`Tests/tcp-http-smoke.py` runs a local TCP server bound to
`127.0.0.1:18080` and a QEMU guest using user-mode NAT. The guest reaches
the fixture at QEMU's standard `10.0.2.2:18080` host address. It recognizes a
unique `NOQERI_NET_OK` body response. **No public internet access or inbound
host-to-guest port forwarding is used.**

The TCP code explicitly refuses any destination other than the QEMU local
gateway. The fixed initial sequence number is test-only and must never be
used for a remotely accessible TCP connection.

## Validation

```sh
NOQERIOS_NETWORK=virtio bash Tests/qemu-smoke.sh
python3 Tests/tcp-http-smoke.py
```

The kernel's COM1 terminal also provides `t` to run the fixture test when
a local server is listening. Without a fixture, it fails after a bounded
number of polls and the shell remains available.

## Still required before calling this a usable TCP/IP stack

- Long-lived connection objects with safe lifetime, resource accounting and
  concurrent socket access, a public socket API, backlog limits and
  permission checks.
- Timer-driven retransmission, duplicate ACK, RTT/RTO estimation,
  SYN/FIN/RST handling, correct orderly close/half-close and TIME_WAIT.
- MSS/PMTU, receive and congestion windows, SACK, reassembly,
  sequence wraparound, out-of-order data, robust TCP options parsing.
- CSPRNG-backed TCP sequence numbers and ephemeral ports.
- DNS general API and caching, IPv6, DHCP renew/rebind, routing table,
  multi-interface failover, ARP cache and spoofing defenses.
- Modern physical Ethernet drivers and broad device matrices.
- TLS 1.3 cryptographic primitives, certificate path/hostname validation,
  entropy and trusted time for HTTPS.
- xHCI and USB Ethernet/phone tethering; Wi-Fi chipset firmware, 802.11 and
  WPA2/WPA3; Bluetooth HCI/L2CAP/PAN; LTE/5G QMI/MBIM modem drivers.

This is strictly an experimental local transport milestone, not a hardened
internet service. Do not connect experimental NoqeriOS devices directly to
untrusted networks.
