#
#  testcase1_1br_2cont.sh
#
# 2nd example. Aim: filter traffic within a single ovs bridge using flows
#
# bridge(s)
# - one bridge br0, no vlan
# containers(s)
# - two busybox containers
# wiring
# - pipeworking one subnet into containers' eth1, so they can l2-see
# flows
# - allow ONLY l2, l3/icmp and l4/443 on bridge
#

# Remove Bridge
ovs-vsctl del-br br0
ovs-vsctl del-br br1
ovs-vsctl add-br br0

# Kill all running containers
docker kill $(docker ps -q -a) >/dev/null

# start and remember two containers
C1=$(docker run -t -d -i busybox /bin/sh)
C2=$(docker run -t -d -i busybox /bin/sh)

# inject networking
pipework br0 $C1 192.168.88.10/24
pipework br0 $C2 192.168.88.11/24

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

# show
docker ps
ovs-vsctl list-br
ovs-vsctl list-ports br0
ovs-ofctl dump-flows br0

C1=$(echo $C1 | cut -b 1-4)
C2=$(echo $C2 | cut -b 1-4)

echo == TESTCASE
echo = l2/l3
echo docker attach $C1 : arping -c 5 -I eth1 192.168.88.11
echo docker attach $C1 : ping 192.168.88.11
echo = l2/l3
echo docker attach $C2 : arping -c 5 -I eth1 192.168.88.10
echo docker attach $C2 : ping 192.168.88.10
echo = l4
echo docker attach $C1 : nc -l -p 443
echo docker attach $C2 : nc 192.168.88.10 443
echo '-> will work'
echo docker attach $C1 : nc -l -p 80
echo docker attach $C1 : nc 192.168.88.11 80
echo '-> will NOT work, because there is no matching flow'
echo == DEBUG
echo run on vm :  watch \'ovs-ofctl dump-flows br0\'
echo 'and watch n_packets flow (or not)'
