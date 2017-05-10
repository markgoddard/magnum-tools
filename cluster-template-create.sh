#!/bin/bash

# Create a magnum cluster template for docker swarm on fedora 25 on baremetal.

FEDORA_RELEASE=25
NAME=swarm-fedora-${FEDORA_RELEASE}
IMAGE=swarm-fedora-${FEDORA_RELEASE}
NET_NAME=swarm-net
SUBNET_NAME=${NET_NAME}
MASTER_FLAVOR=swarm-0
NODE_FLAVOR=swarm-0

# --docker-volume-size must be > 3 to trigger creation of a volume.

magnum cluster-template-create \
--external-network ilab \
--fixed-network ${NET_NAME} \
--fixed-subnet ${SUBNET_NAME} \
--master-flavor ${MASTER_FLAVOR} \
--flavor ${NODE_FLAVOR} \
--image ${IMAGE} \
--name ${NAME} \
--coe swarm \
--network-driver docker \
--docker-storage-driver devicemapper \
--docker-volume-size 3 \
--server-type bm
