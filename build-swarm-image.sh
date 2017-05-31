#!/bin/bash -e

# Build and/or register an image for use with OpenStack magnum using docker
# swarm on fedora 25 on baremetal.

# Partition (not whole disk) images are recommended as they allow for the use
# of an ephemeral partition on the instance which can be used by magnum for
# docker storage.

BUILD=0
REGISTER=0
if [[ $# -gt 0 ]]; then
    if [[ $1 = build ]]; then
        BUILD=1
    elif [[ $1 = register ]]; then
        REGISTER=1
    else
        echo "???"
        exit 1
    fi
else
    BUILD=1
    REGISTER=1
fi

if [[ ! -d stackhpc-image-elements ]]; then
    git clone https://github.com/stackhpc/stackhpc-image-elements
fi

virtualenv dib-venv
source dib-venv/bin/activate
pip install -U pip
# Master is required for dracut-regenerate
pip install git+https://github.com/openstack/diskimage-builder@master
pip install dib-utils python-glanceclient

export ELEMENTS_PATH=$(pwd)/stackhpc-image-elements/elements
export DIB_RELEASE=25
# Enable the [cutting] edge repository.
export DIB_DOCKER_ENABLED_REPOS=docker-ce-edge

# The following is required for --visibility and --os-distro arguments.
export OS_IMAGE_API_VERSION=2

NAME=${NAME:-swarm-ce-fedora-${DIB_RELEASE}}
FILENAME=${FILENAME:-$NAME}
USE_WHOLE_DISK_IMAGE=${USE_WHOLE_DISK_IMAGE:-0}

if [[ $BUILD -eq 1 ]]; then
    echo "Building image"
    if [[ $USE_WHOLE_DISK_IMAGE -eq 0 ]]; then
        disk-image-create \
          baremetal \
          dhcp-all-interfaces \
          dracut-regenerate \
          enable-serial-console \
          fedora \
          grub2 \
          selinux-permissive \
          docker-ce \
          magnum-swarm \
          -o ${FILENAME}.qcow2
    else
        disk-image-create \
          dhcp-all-interfaces \
          dracut-regenerate \
          enable-serial-console \
          fedora \
          selinux-permissive \
          vm \
          docker-ce \
          magnum-swarm \
          -o ${FILENAME}.qcow2
    fi
    echo "Built image"
fi

if [[ $REGISTER -eq 1 ]]; then
    echo "Registering images"
    if [[ $USE_WHOLE_DISK_IMAGE -eq 0 ]]; then
        KERNEL_ID=`glance image-create --name ${NAME}-kernel \
                                       --visibility public \
                                       --disk-format=aki \
                                       --container-format=aki \
                                       --file=${FILENAME}.vmlinuz \
                                       | grep id | tr -d '| ' | cut --bytes=3-57`
        RAMDISK_ID=`glance image-create --name ${NAME}-ramdisk \
                                        --visibility public \
                                        --disk-format=ari \
                                        --container-format=ari \
                                        --file=${FILENAME}.initrd \
                                        | grep id |  tr -d '| ' | cut --bytes=3-57`
        BASE_ID=`glance image-create --name ${NAME} \
                                        --os-distro fedora \
                                        --visibility public \
                                        --disk-format=qcow2 \
                                        --container-format=bare \
                                        --property kernel_id=$KERNEL_ID \
                                        --property ramdisk_id=$RAMDISK_ID \
                                        --file=${FILENAME}.qcow2 \
                                        | grep -v kernel | grep -v ramdisk \
                                        | grep id | tr -d '| ' | cut --bytes=3-57`
    else
        BASE_ID=`glance image-create --name ${NAME} \
                                        --os-distro fedora \
                                        --visibility public \
                                        --disk-format=qcow2 \
                                        --container-format=bare \
                                        --file=${FILENAME}.qcow2 \
                                        | grep -v kernel | grep -v ramdisk \
                                        | grep id | tr -d '| ' | cut --bytes=3-57`
    fi
    echo "Registered images"
fi
