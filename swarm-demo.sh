#!/bin/bash -e

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

FIPS="10.60.253.20 10.60.253.25 10.60.253.29"

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
source ~/os-venv/bin/activate
source ~/mark-openrc.sh
run magnum cluster-config mark-swarm-fedora-25 > swarm-env
deactivate
ls -l
pause

announce "Display dowloaded cluster configuration environment"
run cat swarm-env
pause

announce "Creating a docker overlay network"
run docker network create overlay-net --driver overlay --subnet 10.0.1.0/24
pause

announce "Creating 3 nginx containers"
for i in $(seq 0 2) ; do run docker run -d -p 8080:80 --name nginx-$i --net overlay-net nginx; done
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
