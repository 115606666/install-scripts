#!/usr/bin/env bash

# Version
VER="0.0.1-dev"

# check the --fqdn version, if it's absent fall back to hostname
HOSTNAME=$(hostname --fqdn 2>/dev/null)
if [[ $HOSTNAME == "" ]]; then
  HOSTNAME=$(hostname)
fi

# common ############################################################### START #
if [ ! -v SPINNER ]; then
    SPINNER="/-\|"
fi
log="${PWD}/`basename ${0}`.log"

function error_msg() {
    local MSG="${1}"
    echo "${MSG}"
    exit 1
}

function cecho() {
    echo -e "$1"
    echo -e "$1" >>"$log"
    tput sgr0;
}

function ncecho() {
    echo -ne "$1"
    echo -ne "$1" >>"$log"
    tput sgr0
}

function spinny() {
    if [ -n "$SPINNER" ]; then
        echo -ne "\b${SPINNER:i++%${#SPINNER}:1}"
    fi
}

function progress() {
    ncecho "  ";
    while [ /bin/true ]; do
        kill -0 $pid 2>/dev/null;
        if [[ $? = "0" ]]; then
            spinny
            sleep 0.25
        else
            ncecho "\b\b";
            wait $pid
            retcode=$?
            echo "$pid's retcode: $retcode" >> "$log"
            if [[ $retcode = "0" ]] || [[ $retcode = "255" ]]; then
                cecho success
            else
                cecho failed
                echo -e " [i] Showing the last 5 lines from the logfile ($log)...";
                tail -n5 "$log"
                exit 1;
            fi
            break 2;
        fi
    done
}

function progress_loop() {
    ncecho "  ";
    while [ /bin/true ]; do
        kill -0 $pid 2>/dev/null;
        if [[ $? = "0" ]]; then
            spinny
            sleep 0.25
        else
            ncecho "\b\b";
            wait $pid
            retcode=$?
            echo "$pid's retcode: $retcode" >> "$log"
            if [[ $retcode = "0" ]] || [[ $retcode = "255" ]]; then
                cecho success
            else
                cecho failed
                echo -e " [i] Showing the last 5 lines from the logfile ($log)...";
                tail -n5 "$log"
                exit 1;
            fi
            break 1;
        fi
    done
}

function progress_can_fail() {
    ncecho "  ";
    while [ /bin/true ]; do
        kill -0 $pid 2>/dev/null;
        if [[ $? = "0" ]]; then
            spinny
            sleep 0.25
        else
            ncecho "\b\b";
            wait $pid
            retcode=$?
            echo "$pid's retcode: $retcode" >> "$log"
            cecho success
            break 2;
        fi
    done
}

function check_root() {
    if [ "$(id -u)" != "0" ]; then
        error_msg "ERROR! You must execute the script as the 'root' user."
    fi
}

function check_sudo() {
    if [ ! -n ${SUDO_USER} ]; then
        error_msg "ERROR! You must invoke the script using 'sudo'."
    fi
}

function check_ubuntu() {
    if [ "${1}" != "" ]; then
        SUPPORTED_CODENAMES="${1}"
    else
        SUPPORTED_CODENAMES="all"
    fi

    # Source the lsb-release file.
    lsb

    # Check if this script is supported on this version of Ubuntu.
    if [ "${SUPPORTED_CODENAMES}" == "all" ]; then
        SUPPORTED=1
    else
        SUPPORTED=0
        for CHECK_CODENAME in `echo ${SUPPORTED_CODENAMES}`
        do
            if [ "${LSB_CODE}" == "${CHECK_CODENAME}" ]; then
                SUPPORTED=1
            fi
        done
    fi

    if [ ${SUPPORTED} -eq 0 ]; then
        error_msg "ERROR! ${0} is not supported on this version of Ubuntu."
    fi
}

function lsb() {
    local CMD_LSB_RELEASE=`which lsb_release`
    if [ "${CMD_LSB_RELEASE}" == "" ]; then
        error_msg "ERROR! 'lsb_release' was not found. I can't identify your distribution."
    fi
    LSB_ID=`lsb_release -i | cut -f2 | sed 's/ //g'`
    LSB_REL=`lsb_release -r | cut -f2 | sed 's/ //g'`
    LSB_CODE=`lsb_release -c | cut -f2 | sed 's/ //g'`
    LSB_DESC=`lsb_release -d | cut -f2`
    LSB_ARCH=`dpkg --print-architecture`
    LSB_MACH=`uname -m`
    LSB_NUM=`echo ${LSB_REL} | sed s'/\.//g'`
}
# common ################################################################# END #

function copyright_msg() {
    echo `basename ${0}`" v${VER} - Install frp."
    echo
}

function usage() {
    local MODE=${1}
    echo "## Usage"
    echo
    echo "    sudo ${0}"
    echo
    echo "Optional parameters"
    echo
    echo "  * -m <machine-name>   : Machine name."
    echo "  * -t <token>          : Token."
    echo "  * -a <server address> : Server address."
    echo "  * -p <server port>    : Server port."
    echo "  * -r <remote port>    : Remote port."
    echo "  * -h                     : This help"
    echo
    echo "sudo ./install-frp.sh -m name -t 111 -a server -p 222 -r 333"
}

function check_install() {
    if [ "$FORCE" -eq 0 ] && [ -f /etc/frp/frpc.ini ]; then
        error_msg "FRP already installed, please check or use -f to force install."
    fi
}

function check_jq() {
    ncecho " [x] Check jq "
    if [ ! -f jq ]; then
        wget -qO jq "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" &
    fi
    pid=$!;progress $pid
    chmod +x jq
    chown mike:mike jq
}

function download_frp() {
    local frp_url
    ncecho " [x] Download frp "
    frp_url=`wget -qO- "https://api.github.com/repos/fatedier/frp/releases" | ./jq .[].assets[].browser_download_url | grep linux_amd64 | sed -e 's/^"//' -e 's/"$//' | sort -r | head -n 1`
    FRP_FULLNAME=`basename $frp_url`
    FRP_BASENAME=`echo $FRP_FULLNAME | sed -e 's/.tar.gz//'`
    wget -q $frp_url &
    pid=$!;progress $pid
    tar xfz $FRP_FULLNAME
}

function create_setting() {
    ncecho " [x] Create setting "
    cat > frpc.ini << __EOF
[common]
server_addr = ${SERVER_ADDR}
server_port = ${SERVER_PORT}
token = ${TOKEN}

[${MACHINE_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = ${REMOTE_PORT}
__EOF
    pid=$!;progress $pid
}

function deploy_frp() {
    ncecho " [x] Deploy frp "
    cd $FRP_BASENAME
    cp -f frpc /usr/bin
    mkdir -p /etc/frp
    cp ../frpc.ini /etc/frp
    if [[ -f "systemd/frpc.service" ]]; then
        cp systemd/frpc.service /etc/systemd/system
    else
        wget -O frpc.service https://raw.githubusercontent.com/fatedier/frp/v0.42.0/conf/systemd/frpc.service
        cp frpc.service /etc/systemd/system
    fi
    cd ..
    systemctl enable frpc.service >> /dev/null
    service frpc start &
    pid=$!;progress $pid
}

function clean_all() {
    ncecho " [x] Clean all "
    rm -rf jq frpc.ini install-frp.sh $FRP_FULLNAME $FRP_BASENAME &
    pid=$!;progress $pid
    rm install-frp.sh.log
}

function show_result() {
    echo
    echo $FRP_BASENAME
    echo
    echo ssh -p $REMOTE_PORT $SERVER_ADDR
    echo
}

copyright_msg

# Check we are running on a supported system in the correct way.
check_root
check_sudo
check_ubuntu "all"

# Init variables
MACHINE_NAME=""
TOKEN=""
SERVER_ADDR=""
SERVER_PORT=""
REMOTE_PORT=""
FORCE=0
FRP_FULLNAME="" # frp_0.34.3_linux_amd64.tar.gz
FRP_BASENAME="" # frp_0.34.3_linux_amd64

# Remove a pre-existing log file.
if [ -f $log ]; then
    rm -f $log 2>/dev/null
fi

# Parse the options
OPTSTRING=a:fhm:p:r:t:
while getopts ${OPTSTRING} OPT
do
    case ${OPT} in
        a) SERVER_ADDR=$OPTARG;;
        f) FORCE=1;;
        h) usage;;
        m) MACHINE_NAME=$OPTARG;;
        p) SERVER_PORT=$OPTARG;;
        r) REMOTE_PORT=$OPTARG;;
        t) TOKEN=$OPTARG;;
        *) usage;;
    esac
done
shift "$(( $OPTIND - 1 ))"


cecho MACHINE_NAME=$MACHINE_NAME
cecho SERVER_ADDR=$SERVER_ADDR
cecho SERVER_PORT=$SERVER_PORT
cecho REMOTE_PORT=$REMOTE_PORT
cecho TOKEN=$TOKEN
cecho FORCE=$FORCE
cecho

if [ -z $MACHINE_NAME ]; then
    usage && exit
fi

check_install
check_jq
download_frp
create_setting
deploy_frp
clean_all
show_result
