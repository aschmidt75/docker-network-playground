#
#  testcase1_1br_2cont.sh
#
# 3rd example. Aim: forward l3 traffic between two separate bridges
#
# bridge(s)
# - two bridges br0/br1, no vlan
# containers(s)
# - two busybox containers
# wiring
# - pipeworking each container into one bridge, different subnet
# flows
# - 
# - iptables FORWARD between bridges
#

# Remove Bridge
ovs-vsctl del-br br0
ovs-vsctl del-br br1
ovs-vsctl add-br br0
ovs-vsctl add-br br1

# take an ip on each bridge (the .1), according to subnet
ifconfig br0 192.168.88.1/24
ifconfig br1 192.168.99.1/24

# Kill all running containers
docker kill $(docker ps -q -a) >/dev/null

# start and remember two containers
C1=$(docker run -t -d -i busybox /bin/sh)
C2=$(docker run -t -d -i busybox /bin/sh)

# inject networking, set default route
pipework br0 $C1 192.168.88.10/24@192.168.88.1
pipework br1 $C2 192.168.99.10/24@192.168.99.1

# OVS 
# - remove flows
# - allow (r)arp,icmp
# - allow 443 on bridge
ovs-ofctl del-flows br0
ovs-ofctl add-flow br0 'rarp action=normal'
ovs-ofctl add-flow br0 'arp action=normal'
ovs-ofctl add-flow br0 'icmp action=normal'
ovs-ofctl add-flow br0 'tcp priority=10 tp_dst=443 action=all'
ovs-ofctl add-flow br0 'tcp priority=10 tp_src=443 action=all'

# iptables
iptables -F
iptables -A FORWARD -o br0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i br0 -o br1 -j ACCEPT

# show
docker ps
ovs-vsctl list-br
ovs-vsctl list-ports br0
ovs-ofctl dump-flows br0
iptables -S

C1=$(echo $C1 | cut -b 1-4)
C2=$(echo $C2 | cut -b 1-4)

echo == TESTCASE
echo = l2/l3
echo docker attach $C1 : arping -c 5 -I eth1 192.168.88.1
echo docker attach $C1 : ping 192.168.88.1
echo = l2/l3
echo docker attach $C2 : arping -c 5 -I eth1 192.168.99.1
echo docker attach $C2 : ping 192.168.99.1
echo = l4
echo docker attach $C1 : nc -l -p 443
echo docker attach $C2 : nc 192.168.88.10 443
echo '-> will work, iptables will forward traffic from br0 to br1'
echo = l4
echo docker attach $C1 : nc -l -p 80
echo docker attach $C2 : nc 192.168.88.10 80
echo '-> will NOT work, there is no flow for port 80, regardless of iptables setup'
echo = l4
echo docker attach $C2 : nc -l -p 443
echo docker attach $C1 : nc 192.168.99.10 443
echo '-> will NOT work, iptables will NOT forward traffic from br1 to br0'
