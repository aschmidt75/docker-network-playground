#!/bin/bash

echo = Interfaces on host:

ip link show | grep -E "^[0-9]+: (.*):" | tr -d ':' | awk '{ print $1 " " $2 }'

echo = Peers

for INTF in $(ip link show | grep -E "^[0-9]+: (.*):" | tr -d ':' | awk '{ print $2 }'); do
	PEER=$(ethtool -S $INTF 2>/dev/null | grep "peer_ifindex" | awk '{ print $2 }')
	if [[ ! -z $PEER ]]; then
		echo $INTF	$PEER
	fi
done

echo = Interfaces connected to bridge

for RES in $(ip link show | grep -E '^[0-9]+: (.*): .*master.*' | tr -d ':' | awk '{ print $2 }' ); do
	MASTER=$(ip link show $RES | grep -E "^[0-9]+: (.*):" | sed -e 's/.*master \(.*\) state.*/\1/g')
	if [[ "$MASTER" == "ovs-system" ]]; then
		# query ovs
		MASTER=$(ovs-vsctl iface-to-br $RES)
	fi

	echo $RES  $MASTER
done
