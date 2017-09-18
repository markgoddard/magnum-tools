#!/bin/bash -e

# Script demoing the use of a docker swarm cluster which has been deployed
# via OpenStack magnum.

# These IPs should be set to the floating IP addresses of the Swarm nodes.
FIPS="${FIPS:-10.60.253.17 10.60.253.35 10.60.253.29}"
OPENRC_FILE="${OPENRC_FILE:-/ilab-home/hpcgodd1/mark-openrc.sh}"
VENV="${VENV:-/ilab-home/hpcgodd1/os-venv}"
CLUSTER="${CLUSTER:-mark-swarm-fedora-25}"
DOCKER_VERSION=17.05.0-ce
PAUSE=${PAUSE:-1}

function announce {
    >&2 echo -e "\e[33m$*\e[39m"
}

function run {
    >&2 echo -e "\e[34mRunning: \e[94m$*\e[39m"
    $*
}

function pause {
    >&2 echo -e "\e[34mDone\e[39m"
    if [[ ${PAUSE} = 1 ]]; then
        read
    fi
}

announce "Demo: Docker swarm on OpenStack magnum!"
if [[ ${PAUSE} = 1 ]]; then
    read
fi

MASTER_IP=$(magnum cluster-show ${CLUSTER} | awk '$2 == "master_addresses" { print $4 }' | sed -e 's/\['"'"'//g' -e 's/'"'"'\]//g')
if [[ -z $MASTER_IP ]]; then
    echo "Failed to determine master IP address"
    exit 1
fi

mkdir swarm-demo
cd swarm-demo

announce "Downloading docker client"
run wget https://get.docker.com/builds/Linux/x86_64/docker-${DOCKER_VERSION}.tgz
run tar xzf docker-${DOCKER_VERSION}.tgz
export PATH=$(pwd)/docker:${PATH}
pause

announce "Getting cluster configuration from magnum API"
source "${VENV}/bin/activate"
source "${OPENRC_FILE}"
run magnum cluster-config ${CLUSTER} > swarm-env
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

announce "Cleaning up old state"
if [[ $SWARM_MODE -eq 1 ]]; then
    run docker service rm nginx || true
else
    for i in $(seq 0 2) ; do
        run docker rm -f nginx-$i
    done
fi
run docker network rm overlay-net || true
sleep 10
pause

announce "Creating a docker overlay network"
run docker network create --driver overlay --subnet 10.0.1.0/24 --attachable overlay-net
pause

announce "Creating 3 nginx containers"
if [[ $SWARM_MODE -eq 1 ]]; then
    run docker service create -p 8080:80 --name nginx --network overlay-net --replicas 3 nginx
else
    for i in $(seq 0 2) ; do
        run docker run -d -p 8080:80 --name nginx-$i --net overlay-net nginx
    done
fi
run sleep 10
run docker ps
pause

if [[ $SWARM_MODE -eq 1 ]]; then
    announce "Getting default page from nginx via master"
    run curl http://${MASTER_IP}:8080
else
    announce "Getting default page from nginx via floating IPs"
    for FIP in $FIPS ; do
        run curl http://$FIP:8080
    done
fi
pause

announce "Getting default page from nginx via docker overlay network"
for i in $(seq 2 4); do
    run docker run --rm --net overlay-net tutum/curl curl http://10.0.1.$i
done
pause
