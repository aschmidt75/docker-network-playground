#
#  testcase1_1br_2cont.sh
#
# first example. Aim: connect from host to container via our own bridge
#
# bridge(s)
# - one bridge br0, no vlan
# containers(s)
# - one busybox container
# wiring
# - pipeworking one subnet into container eth1
# - add a tap interface on bridge
#

# Remove Bridge(s), add new
ovs-vsctl del-br br0
ovs-vsctl del-br br1
ovs-vsctl add-br br0

# Kill all running containers
docker kill $(docker ps -q -a) >/dev/null

# start and remember two containers
C1=$(docker run -t -d -i busybox /bin/sh)

# inject networking
pipework br0 $C1 192.168.88.10/24

# add ip to bridge
ifconfig br0 192.168.88.50/24

# show
docker ps
ovs-vsctl list-br br0
ovs-vsctl list-ports br0

ip a s br0

C1=$(echo $C1 | cut -b 1-4)

echo == TESTCASE
echo = l2/l3
echo docker attach $C1 : arping -c 5 -I eth1 192.168.88.50
echo docker attach $C1 : ping 192.168.88.50
echo = l4
echo docker attach $C1 : nc -l -p 443
echo on host : nc 192.168.88.10 443
echo '-> will work'
echo = DEBUG
echo on host: watch \'ovs-ofctl dump-flows br0\'
