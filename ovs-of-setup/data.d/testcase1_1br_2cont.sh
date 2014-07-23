#
#  testcase1_1br_2cont.sh
#
# first example. Aim: establish traffic within a single ovs bridge
#
# bridge(s)
# - one bridge br0, no vlan
# containers(s)
# - two busybox containers
# wiring
# - pipeworking one subnet into containers' eth1, so they can l2-see
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

# show
docker ps
ovs-vsctl list-br br0
ovs-vsctl list-ports br0

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
