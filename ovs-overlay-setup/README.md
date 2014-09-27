# ovs-overlay-setup

*The goal of this demo is to have a pair of containers on different hosts that are able to communication through an overlay network
set up by open vSwitch*

It uses the same setup as the third example, except the bridges are not connected to eth1 of the hosts.

```
$ git clone https://github.com/aschmidt75/docker-network-playground
$ cd ovs-overlay-setup
```

## Overview


```
    +--------------------------------------------------------------+
    |docker-test1 vm                                               |
    |    +-----------------+             +------------------+      |
    |    |        A        |             |         X        |      |
    |    |  192.168.77.10  |             |  192.168.77.20   |      |
    |    |      +----+     |             |     +------+     |      |
    |    +------|eth1|-----+             +-----| eth1 |-----+      |
    |           +--+-+                         +---+--+            |
    |              |                               |               |
    |  +-----------+--------+-+       +-+----------+-----------+   |
    |   br0.100             |           |              br0.101     |
    |                     +-+-----+-----++ br0                     |
    |                             |                                |
    |                         + vtep0 +                            |
    |                       //                                     |
    |                     //   +------+                            |
    +--------------------||----| eth1 |----------------------------+
                        o||    +------+
                        v||        |
                        e||        |       virtualbox vnet3
            +-----------r||------+-+------------------------+
                        l||      |
                        a||      |
                        y||    +-+----+
    +--------------------||----| eth1 |----------------------------+
    |docker-test2 vm     \\    +--+---+                            |
    |                      \\                                      |
    |                        \\+ vtep0 +                           |
    |                             |                                |
    |                    +--+-----+-------+-----------+ br0        |
    |  br0.100              |             |                br0.101 |
    |  +---------+----------+--+       +--+--------+----------+    |
    |            |                                 |               |
    |            |                                 |               |
    |          +-+--+                          +---+-+             |
    |  +-------|eth1|----------+          +----|eth1 |--------+    |
    |  |       +----+          |          |    +-----+        |    |
    |  |   192.168.77.11       |          |  192.168.77.21    |    |
    |  |          B            |          |         Y         |    |
    |  +-----------------------+          +-------------------+    |
    +--------------------------------------------------------------+
    
```

The Vagrantfile defines two vms, `docker-test1` and `docker-test2`, that
are connected to a network on the host, configured as an eth1.

Both VMs will get a Open vSwitch bridge setup with a parent bridge `br0`
(untagged, "trunk") and two VLAN-tagged bridges, `br0.100` and `br0.101`
that get the vlan ids of 100 and 101. 

Bridges will also have a port "vtep0", a virtual tunnel endpoint of type vxlan, 
with a key (VNI) and the remote ip, like

`ovs-vsctl add-port br0 vtep0 -- set interface vtep0 type=vxlan options:key=4711 options:remote_ip=$REMOTE_IP`

We will then start two containers on each vm. Using pipework, we
- attach one container to bridge with VLAN ID 100, give it an ip address of 192.168.77.10/.20,
- attach one container to bridge with VLAN ID 101, give it 192.168.77.11/.21

So in the end,
- A can talk to B
- X can talk to Y
- But A/B cannot talk to X/Y

To make things easier, we code this setup in a script `setup_1vlans_2containers_overlay.sh` in `data.d/` (mapped to `/srv` in vm).

## Setup

```
$ vagrant up
```

Open two screen sessions, then `vagrant ssh` into the vms:

```
$ vagrant ssh docker-test1
$ sudo -i
```

```
$ vagrant ssh docker-test2
$ sudo -i
```

Then on each vm, as root:
```bash
# cd /srv
# ./setup_1vlans_2containers_overlay.sh

ovs-vsctl: no port named gre0
ovs-vsctl: no port named vtep0
ovs-vsctl: no bridge named br0.100
ovs-vsctl: no bridge named br0.101
ovs-vsctl: no bridge named br0
overlay: LOCAL_IP=192.168.77.26/24
overlay: REMOTE_IP=192.168.77.25
CONTAINER ID        IMAGE               COMMAND                CREATED             STATUS              PORTS               NAMES
6d2d8e1af4b3        test/1:latest       /bin/sh -c 'while !    2 seconds ago       Up 2 seconds        22/tcp              stoic_sinoussi
69dd55c0a78a        test/1:latest       /bin/sh -c 'while !    2 seconds ago       Up 2 seconds        22/tcp              drunk_engelbart
use "docker logs" to see ping statements:
docker logs -f 69dd55c0a78ae7221877af168a6622899828319aa17f94679954ae51599d27ea
docker logs -f 6d2d8e1af4b34aa3ca96cf48c30debb4f68928e91b5ee5124a3b34db02eca89a
```

Each container constantly pings the other one. 
```bash
# docker logs 69dd55c0a78ae7221877af168a6622899828319aa17f94679954ae51599d27ea | head -20
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
19: eth1: <NO-CARRIER,BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state DOWN group default qlen 1000
    link/ether 9e:d5:53:5f:c3:07 brd ff:ff:ff:ff:ff:ff
    inet 192.168.99.11/24 scope global eth1
       valid_lft forever preferred_lft forever
    inet6 fe80::9cd5:53ff:fe5f:c307/64 scope link tentative
       valid_lft forever preferred_lft forever
PING 192.168.99.10 (192.168.99.10) 56(84) bytes of data.
64 bytes from 192.168.99.10: icmp_seq=1 ttl=64 time=0.062 ms
64 bytes from 192.168.99.10: icmp_seq=2 ttl=64 time=0.461 ms
64 bytes from 192.168.99.10: icmp_seq=3 ttl=64 time=0.688 ms
(...)
```

Use tcpdump on either vm to see what's happening on eth1:
```bash
root@dt-1:/srv# tcpdump -i eth1 -vvv
tcpdump: listening on eth1, link-type EN10MB (Ethernet), capture size 65535 bytes
15:30:54.401160 IP (tos 0x0, ttl 64, id 65391, offset 0, flags [DF], proto UDP (17), length 138)
    dt-1.41722 > 192.168.77.26.4789: [no cksum] VXLAN, flags [I] (0x08), vni 4711
IP (tos 0x0, ttl 64, id 59865, offset 0, flags [DF], proto ICMP (1), length 84)
    192.168.99.10 > 192.168.99.11: ICMP echo request, id 11, seq 160, length 64
15:30:54.401644 IP (tos 0x0, ttl 64, id 650, offset 0, flags [DF], proto UDP (17), length 138)
    192.168.77.26.41722 > dt-1.4789: [no cksum] VXLAN, flags [I] (0x08), vni 4711
IP (tos 0x0, ttl 64, id 57706, offset 0, flags [none], proto ICMP (1), length 84)
    192.168.99.11 > 192.168.99.10: ICMP echo reply, id 11, seq 160, length 64
15:30:54.403269 IP (tos 0x0, ttl 64, id 651, offset 0, flags [DF], proto UDP (17), length 138)
    192.168.77.26.41722 > dt-1.4789: [no cksum] VXLAN, flags [I] (0x08), vni 4711
```

One can see the overlay packages (IPs 192.168.77.x), type VXAN, VNI=4711 and
the inner packages (OPs 192.168.99.x, ICMP echo requests and replies)

Check connectivity breaks by i.e. taking down eth1 on the second vm while watching tcpdump on the first vm:
`ip link set eth1 down` and `ip link set eth1 up`
or taking down the vtep or misconfiguring it, i.e. 

```
# ovs-vsctl del-port vtep0
(...)
# # wrong vni
# ovs-vsctl add-port br0 vtep0 -- set interface vtep0 type=vxlan options:key=9999 options:remote_ip=192.168.77.25

# correct vni again
# ovs-vsctl del-port vtep0
# ovs-vsctl add-port br0 vtep0 -- set interface vtep0 type=vxlan options:key=4711 options:remote_ip=192.168.77.25
```

