#!/bin/bash

if [[ `id -u` != 0 ]]; then
	echo Must run as root, exiting.
	exit 1
fi

# kill old containers

MY_CONTS=$(docker ps | grep "test\/1" | awk '{ print $1 }')
docker stop $MY_CONTS

# set up bridges

ovs-vsctl del-br br0.100
ovs-vsctl del-br br0.101
ovs-vsctl del-br br0

ovs-vsctl add-br br0
ovs-vsctl add-br br0.100 br0 100
ovs-vsctl add-br br0.101 br0 101

ovs-vsctl add-port br0 eth1

# start containers
C1=$(docker run -P -d test/1)
C2=$(docker run -P -d test/1)

# choose ip address according to hostname
IP1=
IP2=
if [[ "`hostname -s`" == "dt-1" ]]; then
	IP1=10
	IP2=20
fi
if [[ "`hostname -s`" == "dt-2" ]]; then
	IP1=11
	IP2=21
fi

# connect to bridges
pipework br0.100 $C1 192.168.77.${IP1}/24
pipework br0.101 $C2 192.168.77.${IP2}/24

docker ps

