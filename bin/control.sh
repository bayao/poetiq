#!/bin/bash

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $BIN/util.sh
source $BIN/setenv.sh

if [ -z $QBIN ]; then logerr "Q binary not found"; fi

# exit script or send interrupt signal to stop execution of function if in console mode
function exit_or_return ()
{
	if [ -z "$PS1" ]; then exit $1; else kill -INT $$; fi
}

function check_cfg_exists ()
{
	if [ ! -f $KDBCONFIG/start.csv ]; then
		local m="Config file $KDBCONFIG/start.csv not found"
		if [ ${FUNCNAME[1]} == "show" ]; then
			logerr "$m"
		else
			logerr "$m"
		fi
		exit 1
	fi
}

function get_procs ()
{
	check_cfg_exists
	tail -n +2 $KDBCONFIG/start.csv | cut -d ',' -f 1,2
}

function get_params ()
{
	unset PROCTYPE PROCNAME W G LOGTYPE LOGN LOGWAIT CUSTOM_ARGS
	LOGLEVEL=""
	DEBUG=0
	caller=${FUNCNAME[1]}

	if [ $# -lt 2 ]; then
		${caller}_usage $caller
		return 2
	fi

	PROCTYPE=$1
	PROCNAME=$2
	if [ -z "${PROCTYPE}" ] || [ -z "${PROCNAME}" ]; then
		logerr "Proc type and proc name must be specified"
		return 2
	fi
	shift 2

	while (( "$#" )); do
		case "$1" in
			-w) # get workspace size
				if [ -z "$2" ]; then ${caller}_usage $caller; fi
				W="$1 $2"
				shift 2
			;;
			-g) # garbage collect
				if [ -z "$2" ]; then ${caller}_usage $caller; fi
				G="$2"
				shift 2
			;;
			--debug) # run process in foreground
				DEBUG=1
				shift
			;;
			--log) # get log level
				if [ -z "$2" ]; then ${caller}_usage $caller; fi
				LOGLEVEL="$2"
				shift 2
			;;
			-t) # get log type
				if [ -z "$2" ]; then ${caller}_usage $caller; fi
				# if [[ ! "$2" =~ "out|err|usage" ]]; then ${caller}_usage $caller; fi
				LOGTYPE="$2"
				shift 2
			;;
			-n) # get number of log lines
				if [ -z "$2" ]; then ${caller}_usage $caller; fi
				LOGN="$2"
				shift 2
			;;
			-[fF]) # get log wait/stream flag
				LOGWAIT=1
				shift
			;;
			--args) # args will consume the remaining args
				shift
				CUSTOM_ARGS="$@"
				break
			;;
			*) ${caller}_usage $caller;;
		esac
	done
	if [ $? -eq 2 ]; then return 2; fi
}

function get_cmd()
{
	CMD="$QBIN $(grep "$PROCTYPE,$PROCNAME" $KDBCONFIG/start.csv | cut -d ',' -f 3)"

	if [[ ! -z $CUSTOM_ARGS ]]; then CMD+=" $CUSTOM_ARGS"; fi

	if [ $DEBUG -ne 0 ]; then
		# Use rlwrap if available
		if hash rlwrap 2>/dev/null; then CMD="rlwrap $CMD"; fi
		CMD+=" -debug 1b"
	elif [[ "$OSTYPE" =~ darwin*|linux*|bsd*|solaris* ]]; then
		CMD="nohup $CMD </dev/null >${KDBLOG}/${PROCNAME}.txt 2>&1 &"
	fi

	CMD=$(eval echo \""${CMD}"\")
}

# main start function
function startp ()
{
	get_params $*
	if [ $? -eq 2 ]; then return 0; fi
	starth
}

function starth ()
{
	check_cfg_exists
	queryh
	if [ -n "$PID" ]; then
		logwarn "$(procname) is already running. Use restart if you want to restart the process."
		return 0
	fi
	get_cmd

	if [ $DEBUG -eq 0 ]; then
		loginfo "Starting process $(procname) in the background"
	else
		loginfo "Starting process $(procname) in the foreground"
	fi
	# echo $CMD
	eval $CMD
}

function startp_usage ()
{
	echo -e "Usage:"
	echo -e "\t${1} <proctype> <procname> [-w <size>] [--log <loglevel>] [--debug] [--args <customargs>]"
	exit_or_return 1
}

# main query function
function queryp ()
{
	get_params $*
	if [ $? -eq 2 ]; then return 0; fi
	queryh
	if [ -z "$PID" ]; then
		loginfo "$(procname) is ${UNDERLINE}not${NORMAL} running"
		return 0
	else
		loginfo "$(procname) is running with PID = $PID"
		return 1
	fi
}

function queryh ()
{
	unset PID
	if [[ "$OSTYPE" =~ darwin* ]]; then
		PID=$(ps -e -o 'pid,args' | grep -E "\-(proctype.*procname)" | grep m32 | grep "$PROCTYPE" | grep "$PROCNAME" | awk '{print $1}')
	elif [ "$OSTYPE" == "cygwin" ]; then
		PID=$(pstree -pal | grep -E "\-(proctype.*procname)" | grep -v grep | grep -F "$PROCTYPE" | grep -F "$PROCNAME" | awk -F, '{print $2)' | awk '{print $1}')
	else
		PID=$(ps -elf | grep -E "\-(proctype.*procname)" | grep -E "l32|l64" | grep "$PROCTYPE" | grep "$PROCNAME" | awk '{print $4}')
	fi
}

function queryp_usage ()
{
	echo -e "Usage:"
	echo -e "\t${1} <proctype> <procname>"
	exit_or_return 1
}

# main stop function
function stopp ()
{
	get_params $*
	if [ $? -eq 2 ]; then return 0; fi
	stoph
}

function stoph ()
{
	queryh
	if [ -n "$PID" ]; then
		loginfo "Stopping $(procname)"
		if [ "$OSTYPE" == "cygwin" ]; then
			kill $PID
		else
			# TODO: Exit more gracefully
			kill $PID
		fi
	fi
}

function stopp_usage ()
{
	echo -e "Usage:"
	echo -e "\t${1} <proctype> <procname>"
	exit 1
}

function stopallp ()
{
	mkfifo procpipe && (listp | tail -n +2 > procpipe &)
	while read -r line; do
		PROCTYPE=$(echo $line | awk '{print $2}')
		PROCNAME=$(echo $line | awk '{print $3}')
		stoph
	done < procpipe; rm procpipe
	unset PROCTYPE PROCNAME
}

function listp ()
{
	local REGEX="([0-9]+).*-proctype ([A-Za-z0-9_-]+).*-procname ([A-Za-z0-9_-]+).*"
	local OUTPUT="PID\tPROCTYPE\tPROCNAME"

	if [[ $OSTYPE =~ darwin* ]]; then
		local CMD="ps -e -o 'pid,args'"
	else
		local CMD="ps -elf"
	fi

	mkfifo listpipe && (eval $CMD > listpipe &)
	while read -r line; do
		if [[ $line =~ $REGEX ]]; then
			OUTPUT+="\n${BASH_REMATCH[1]}\t${BASH_REMATCH[2]}\t${BASH_REMATCH[3]}"
		fi
	done < listpipe; rm listpipe

	echo -e $OUTPUT | column -t -s $'\t' | sort -k 2
}

function restartp ()
{
	get_params $*
	if [ $? -eq 2 ]; then return 0; fi
	stoph
	starth
}

function restartp_usage ()
{
	startp_usage $1
}

function tailp ()
{
	get_params $*
	if [ $? -eq 2 ]; then return 0; fi
	local LOGFILE=$KDBLOG/${LOGTYPE}_${PROCNAME}.log

	if [ -z $LOGTYPE ]; then tailp_usage; return 2; fi
	if [ ! -h "$LOGFILE" ]; then
		logerr "No log file found for $(procname)"
		exit_or_return 1
	fi

	local CMD="tail"
	if [ ! -z $LOGN ]; then CMD+=" -n $LOGN"; fi
	if [ ! -z $LOGWAIT ]; then CMD+=" -F"; fi
	CMD+=" $LOGFILE"

	eval ${CMD}
}

function tailp_usage ()
{
	echo -e "Usage:"
	echo -e "\t${1} <proctype> <procname> -t <out|err|usage> [-n <lines>] [-F]"
	exit_or_return 1
}

function procname ()
{
	echo "${POWDER_BLUE}<${PROCTYPE} ${PROCNAME}>${NORMAL}"
}

export -f queryp
export -f startp
export -f stopp
export -f stopallp
export -f restartp
export -f listp
export -f tailp
