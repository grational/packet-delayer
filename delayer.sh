#!/usr/bin/env bash
set -euo pipefail
declare exe="${0##*/}"

best_effort() { # {{{
	${@} &>/dev/null || true
} # }}}

printline() { # {{{
	local -i line_lenght=${1}
	printf "%.s=" $(seq 1 "${line_lenght}"); echo
} # }}}

echoxec() { # {{{
	local command="${*}"
	local line_lenght=${#command}
	(( $line_lenght > $(tput cols) )) && line_lenght=$(tput cols)
	printline $line_lenght
	echo $command
	printline $line_lenght
	${@} # execute the command afterward
} # }}}

usage() { # {{{
	echo
	echo "- To list all the discipline queues of a specific interface:"
	echo "    $exe list <iface>                  # e.g.: $exe list eth0"
	echo
	echo "- To list all the discipline queues on all the net interfaces:"
	echo "    $exe list"
	echo
	echo "- To add a delay to all outgoing connections:"
	echo "    $exe add <delay>                   # e.g.: $exe add 200ms"
	echo
	echo "- To add a delay through a specific interface:"
	echo "    $exe add <delay> <iface>           # e.g.: $exe add 200ms eth0"
	echo
	echo "- To add a delay towards a specific host or ip:"
	echo "    $exe add <delay> <ip|host>         # e.g.: $exe add 200ms api.example.com"
	echo
	echo "- To reset the discipline queue on all the net interfaces:"
	echo "    $exe reset"
	echo
	echo "- To reset the discipline queue of a specific interface:"
	echo "    $exe reset <iface>                 # e.g.: $exe reset eth0"
	echo
	exit 0
} # }}}

all_interfaces() { # {{{
	ip link show | awk -F': ' '/^[1-9]+:/ {print $2}'
} # }}}

process_add() { # {{{
	local delay=${1} && shift
	local ip_address=''
	local iface=''
	if (( ${#@} > 0 )); then
		if getent hosts ${1} &> /dev/null; then
			ip_address="$(getent hosts "${1}" | cut -d' ' -f1)"
		elif [[ ${1} =~ ^([0-9]{1,3}[.]){3}[0-9]{1,3}$ ]]; then
			ip_address=$1
		elif ifconfig | grep "$1" &>/dev/null; then
			iface="${1}"
		else
			iface="$(route | awk '/^default/ {print $8}')"
			echo 2>&1 "Device $1 not found, using $iface as default"
		fi
		# set iface if a ip address has been passed
		[[ $ip_address ]] && iface="$(ip route get $ip_address | grep -oP "^$ip_address.*dev \K\S+")"
	fi
	
	# reset all the previous qdisc rules
	echoxec best_effort sudo tc qdisc del dev "$iface" root
	
	if [[ $ip_address ]]; then
		# attach a priority queue (three levels: 0,1,2) to the root one
		echoxec sudo tc qdisc add dev "$iface" root handle 1: prio
		# add a delay of $delay to the priority queue 2
		echoxec sudo tc qdisc add dev "$iface" parent 1:1 handle 2: netem delay "$delay"
		# move the traffic going towards $ip_address to it
		echoxec sudo tc filter add dev "$iface" parent 1:0 protocol ip pref 55 handle ::55 u32 match ip dst "$ip_address" flowid 2:1
	else
		if [[ $iface ]]; then
			echoxec sudo tc qdisc add dev $iface root netem delay $delay
		else
			for iface in $(all_interfaces); do
				# add delay to all the traffic going out through netdevice
				echoxec sudo tc qdisc add dev $iface root netem delay $delay
			done
		fi
	fi
} # }}}

process_reset() { # {{{
	if (( ${#@} > 0 )); then
		echoxec best_effort sudo tc qdisc del dev "$1" root
	else
		for iface in $(all_interfaces); do
			# reset all the previous qdisc rules
			echoxec best_effort sudo tc qdisc del dev "$iface" root
		done
	fi
} # }}}

process_list() { # {{{
	if (( ${#@} > 0 )); then
		echoxec tc qdisc list dev $1
	else
		echoxec tc qdisc list
	fi
} # }}}

(( ${#@} < 1 )) && usage

# parsing main command # {{{
readonly cmd="$1"

case "$cmd" in
	add)
		shift && process_add "${@}" ;;
	reset)
		shift && process_reset "${@}";;
	list)
		shift && process_list "${@}";;
	*)
		usage ;;
esac
# }}}

exit 0
# vim: fdm=marker
