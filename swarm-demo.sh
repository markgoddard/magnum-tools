#!/bin/bash -e

# Script demoing the use of a docker swarm cluster which has been deployed
# via OpenStack magnum.

# These IPs should be set to the floating IP addresses of the Swarm nodes.
FIPS="${FIPS:-10.60.253.17 10.60.253.35 10.60.253.29}"
OPENRC_FILE="/ilab-home/hpcgodd1/mark-openrc.sh"
VENV="/ilab-home/hpcgodd1/os-venv"
STACK="mark-swarm-fedora-25"

function announce {
    >&2 echo -e "\e[33m$*\e[39m"
}

function run {
    >&2 echo -e "\e[34mRunning: \e[94m$*\e[39m"
    $*
}

function pause {
    >&2 echo -e "\e[34mDone\e[39m"
    read
}

announce "Demo: Docker swarm on OpenStack magnum!"
read

mkdir swarm-demo
cd swarm-demo

announce "Downloading docker client"
run wget https://get.docker.com/builds/Linux/x86_64/docker-1.12.6.tgz
run tar xzf docker-1.12.6.tgz
export PATH=${PATH}:$(pwd)/docker
pause

announce "Getting cluster configuration from magnum API"
source "${VENV}/bin/activate"
source "${OPENRC_FILE}"
run magnum cluster-config ${STACK} > swarm-env
deactivate
ls -l
pause

announce "Display dowloaded cluster configuration environment"
run cat swarm-env
source swarm-env
pause

if docker info | grep 'Swarm: active' >/dev/null; then
    SWARM_MODE=1
fi

announce "Creating a docker overlay network"
run docker network create overlay-net --driver overlay --subnet 10.0.1.0/24
pause

announce "Creating 3 nginx containers"
if [[ $SWARM_MODE -eq 1 ]]; then
    run docker service create -p 8080:80 --name nginx --network overlay-net --replicas 3 nginx
else
    for i in $(seq 0 2) ; do run docker run -d -p 8080:80 --name nginx-$i --net overlay-net nginx; done
fi
run docker ps
pause

announce "Getting default page from nginx via floating IPs"
for FIP in $FIPS ; do
    run curl http://$FIP:8080
done
pause

announce "Getting default page from nginx via docker overlay network"
for i in $(seq 2 4); do
    run docker run --rm --net overlay-net tutum/curl curl http://10.0.1.$i
done
pause
