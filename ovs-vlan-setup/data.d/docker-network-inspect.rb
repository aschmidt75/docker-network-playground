#!/usr/bin/env ruby
#
# docker-network-inspect.rb
#
# The MIT License (MIT)
# Copyright (c) 2014 Andreas Schmidt
# 
# Shows container interfaces, their mapping to virtual interfaces
# on docker host and their mapping to bridges on the host.
# Works only for containers that have interface(s) attached by pipework
# Uses ethtool, bcrtl, ovs-vsctl, ip netns to query data. 
# Open vSwitch is optional
#
# Usage:
#  docker-network-inspect.rb <CONTAINER-ID>
#
# Exit codes:
# 0 - ok, see output
# 1 - unable to locate necessary binaries (i.e. ethtool, brctl)
# 2 - no container id given
# 3 - unable to query pid of container
# 4 - unable to query bridge of container
# 

# locate binaries
#
def locate_binary_or_fail(name)
	n = locate_binary name
	if !(File.executable?(n)) then
		STDERR.puts "ERROR Unable to locate #{name} binary"
		exit 1
	end
	n
end
def locate_binary(name)
	(`which #{name}` || "").chomp  
end

# locate the binaries we need
$docker_bin = locate_binary_or_fail 'docker'
$ethtool_bin = locate_binary_or_fail 'ethtool'
$ip_bin = locate_binary_or_fail 'ip'
$ovsvsctl_bin = locate_binary 'ovs-vsctl'


# read container interfaces, via network namespaces
# return a map, key: interface name, value: interface id
#
def build_container_interface_map(namespace)
	res = {}
	open("|ip netns exec #{namespace} ip link show") do |f|
		r = /^([0-9]+): (.*): </
		f.each do |line|
			md = line.match r
			if md && md.size >= 2 then
				e = { :id => md[1] } 

				res.store(md[2],e)
			end
		end
	end
	res
end

# read host interface config, find peers
# return map containing maps by name, by id, by peer_id
# 
def build_host_interface_map
	by_name_res = {}
	by_id_res = {}
	by_peer_id_res = {}
	res = { :by_name => by_name_res, :by_id => by_id_res, :by_peer_id => by_peer_id_res }
	open('|ip link show') do |f|
		r = /^([0-9]+): (.*): </
		rm = /master (.*) state.*/
		f.each do |line|
			md = line.match r
			if md && md.size >= 2 then
				e = { :id => md[1] } 

				# run ethtool to find peer
				peer_id = `#{$ethtool_bin} -S #{md[2]} 2>/dev/null | grep peer_ifindex`.chomp.split.at(-1)
				if peer_id && peer_id.size > 0
					e.store :peer_id, peer_id
					by_peer_id_res.store peer_id, md[2]
				end


				# find master 
				mdm = line.match rm
				if mdm && mdm.size >= 2 
					e.store :master, mdm[1] 	

					# set flag if managed by open vswitch
					e.store :ovs, true 	if mdm[1] == 'ovs-system'
				end

				by_name_res.store(md[2],e)
				by_id_res.store(md[1],md[2])
			end
		end
	end
	res
end

# run brctl show and parse output. 
# Return a map, key: bridge name, value: Array of interface names
def read_brctl_show
	res = {}
	open('|sudo brctl show') do |f|
		f.readline		# skip first
		br = nil
		f.each do |line|
			if line =~ /^[a-zA-Z0-9_]/ then
				br = (line.split)[0]
				res.store(br,[])
			else
				iface = line.chomp.strip
				res[br] << iface
			end

		end
	end
	res
end

# given an interface name, this methods locates the bridge 
# it is attached to.
# Return a map with bridge data (may be empty if bridge not found).
# Uses brctl and ovs-vsctl. When using ovs, this also queries 
# the parent bridge (if any) and vlan (if set)
#
def locate_bridge_for_iface(name)
	br_res = {
		:type => :unknown,
		:bridge => nil
	}

	# try to locate with bridge utils
	read_brctl_show.each do |bridge,ifaces|
		br_res[:bridge] = bridge if ifaces.include? name
		br_res[:type] = :linuxbridge
	end
	if br_res[:bridge].nil? then
		# not found? -> find out if this interface is managed by open vswitch
		if $ovsvsctl_bin then
			br = `#{$ovsvsctl_bin} iface-to-br #{name} 2>/dev/null`.chomp
			br_res[:bridge] = br
			br_res[:type] = :ovs

			# locate parent and vlan
			p = `#{$ovsvsctl_bin} br-to-parent #{br} 2>/dev/null`.chomp
			br_res[:parent] = p if p && p.size > 0

			vlan = `#{$ovsvsctl_bin} br-to-vlan #{br} 2>/dev/null`.chomp
			br_res[:vlan] = vlan if vlan && vlan.size > 0 
		end
	end
	br_res

end

# expect first parameter to be id of running docker container
if ARGV && ARGV.size < 1 then
	STDERR.puts "#{$0} <CONTAINER-ID>"
	exit 2
end

$container_id = ARGV[0]
puts "CONTAINER #{$container_id}"

# get process id from container id
$process_id = `#{$docker_bin} inspect -f '{{ .State.Pid }}' #{$container_id} 2>/dev/null`.chomp
if $? != 0 then
	STDERR.puts "ERROR Unable to find process id for container #{$container_id}"
	exit 3
else
	puts "+ PID #{$process_id}"
end

# find default bridge
$bridge_name = `#{$docker_bin} inspect -f '{{ .NetworkSettings.Bridge }}' #{$container_id} 2>/dev/null`
if $? != 0 then
	STDERR.puts "ERROR Unable to inspect bridge name for container #{$container_id}"
	exit 4
end


# find out if this process is manageable via netns
`#{$ip_bin} netns show #{$process_id} 2>/dev/null | grep -q #{$process_id}`
if $? == 0 then
	# yes, use network namespace facility of ip tool to read interfaces
	
	# build a map of all interfaces and bridges on host
	$host_ifaces = build_host_interface_map

	container_ifaces = build_container_interface_map($process_id)
	puts "+ INTERFACES"
	container_ifaces.each do |iface_name, iface_id|
		puts " + #{iface_name} (#{iface_id[:id]})"

		# check if iface_id is a peer id, using the host_ifaces map
		host_peer = ($host_ifaces[:by_peer_id])[iface_id[:id]]
		if host_peer then
			host_peer_id = (($host_ifaces[:by_name])[host_peer] || {})[:id]
			puts "  + HOST PEER #{host_peer} (#{host_peer_id})"


			# locate the bridge this interface is attached to
			on_bridge = locate_bridge_for_iface host_peer
			if on_bridge 
				puts "   + BRIDGE #{on_bridge[:bridge]}"
				if on_bridge[:type] == :ovs then
					puts "    + VLAN   #{on_bridge[:vlan]}" if on_bridge[:vlan]
					puts "    + PARENT #{on_bridge[:parent]}" if on_bridge[:parent]
				end
			end
		end
	end
else
	puts "- NOT managed by network namespaces."
	# Cannot continue, unfortunately
end

