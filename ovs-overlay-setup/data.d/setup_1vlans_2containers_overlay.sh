#!/bin/bash

if [[ `id -u` != 0 ]]; then
	echo Must run as root, exiting.
	exit 1
fi

# kill old containers

MY_CONTS=$(docker ps | grep "test\/1" | awk '{ print $1 }')
if [[ ! -z $MY_CONTS ]]; then
	docker stop $MY_CONTS
fi

# set up bridges

ovs-vsctl del-port gre0
ovs-vsctl del-port vtep0
ovs-vsctl del-br br0.100
ovs-vsctl del-br br0.101
ovs-vsctl del-br br0

ovs-vsctl add-br br0
ovs-vsctl add-br br0.100 br0 100
ovs-vsctl add-br br0.101 br0 101

# set up overlay network
# find out remote ip
LOCAL_IP=`ip a s eth1 | grep -E 'inet ' | awk '{ print $2 }'`
REMOTE_IP=
[[ "$LOCAL_IP" == "192.168.77.26/24" ]] && REMOTE_IP=192.168.77.25
[[ "$LOCAL_IP" == "192.168.77.25/24" ]] && REMOTE_IP=192.168.77.26
echo overlay: LOCAL_IP=$LOCAL_IP
echo overlay: REMOTE_IP=$REMOTE_IP

# GRE 
#ovs-vsctl add-port br0 gre0 -- set interface gre0 type=gre options:remote_ip=$REMOTE_IP

# VxLAN, VNI=4711
ovs-vsctl add-port br0 vtep0 -- set interface vtep0 type=vxlan options:key=4711 options:remote_ip=$REMOTE_IP

# start containers
#C1=$(docker run -P -d test/1)
#C2=$(docker run -P -d test/1)

# choose ip address according to hostname
IP1=
IP2=
if [[ "`hostname -s`" == "dt-1" ]]; then
	C1=$(docker run --net=none -d test/1 /bin/sh -c 'while ! grep -q ^1$ /sys/class/net/eth1/carrier 2>/dev/null; do sleep 1; done; ip a s; ping 192.168.99.11')
	C2=$(docker run --net=none -d test/1 /bin/sh -c 'while ! grep -q ^1$ /sys/class/net/eth1/carrier 2>/dev/null; do sleep 1; done; ip a s; ping 192.168.99.21')
	IP1=10
	IP2=20
fi
if [[ "`hostname -s`" == "dt-2" ]]; then
	C1=$(docker run --net=none -d test/1 /bin/sh -c 'while ! grep -q ^1$ /sys/class/net/eth1/carrier 2>/dev/null; do sleep 1; done; ip a s; ping 192.168.99.10')
	C2=$(docker run --net=none -d test/1 /bin/sh -c 'while ! grep -q ^1$ /sys/class/net/eth1/carrier 2>/dev/null; do sleep 1; done; ip a s; ping 192.168.99.20')
	IP1=11
	IP2=21
fi

# connect to bridges
pipework br0.100 $C1 192.168.99.${IP1}/24
pipework br0.101 $C2 192.168.99.${IP2}/24

docker ps

echo use \"docker logs\" to see ping statements:
echo docker logs -f $C1
echo docker logs -f $C2

