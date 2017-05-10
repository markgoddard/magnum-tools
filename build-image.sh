#!/bin/bash -e

# Build and/or register an image for use with OpenStack magnum using docker
# swarm on fedora 25 on baremetal.

# Currently the magnum kubernetes baremetal DIB element is being used as
# there is no DIB element for swarm on fedora on baremetal.

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

virtualenv dib-venv
source dib-venv/bin/activate
pip install -U pip
pip install git+https://github.com/stackhpc/diskimage-builder@stackhpc-2.3.3
pip install dib-utils python-glanceclient

if [[ ! -d magnum ]]; then
    git clone https://git.openstack.org/openstack/magnum
fi
export ELEMENTS_PATH=magnum/magnum/drivers/k8s_fedora_ironic_v1/image
export DIB_RELEASE=25

# The following is required for --visibility and --os-distro arguments.
export OS_IMAGE_API_VERSION=2

NAME=${NAME:-swarm-fedora-${DIB_RELEASE}}
USE_WHOLE_DISK_IMAGE=${USE_WHOLE_DISK_IMAGE:-0}

if [[ $BUILD -eq 1 ]]; then
    if [[ $USE_WHOLE_DISK_IMAGE -eq 0 ]]; then
        disk-image-create \
          baremetal \
          dhcp-all-interfaces \
          dracut-network \
          enable-serial-console \
          fedora \
          grub2 \
          selinux-permissive \
          kubernetes \
          -o fedora-${DIB_RELEASE}.qcow2
    else
        disk-image-create \
          dhcp-all-interfaces \
          dracut-network \
          enable-serial-console \
          fedora \
          selinux-permissive \
          vm \
          kubernetes \
          -o fedora-${DIB_RELEASE}.qcow2
    fi
fi

if [[ $REGISTER -eq 1 ]]; then
    if [[ $USE_WHOLE_DISK_IMAGE -eq 0 ]]; then
        KERNEL_ID=`glance image-create --name ${NAME}-kernel \
                                       --visibility public \
                                       --disk-format=aki \
                                       --container-format=aki \
                                       --file=fedora-${DIB_RELEASE}.vmlinuz \
                                       | grep id | tr -d '| ' | cut --bytes=3-57`
        RAMDISK_ID=`glance image-create --name ${NAME}-ramdisk \
                                        --visibility public \
                                        --disk-format=ari \
                                        --container-format=ari \
                                        --file=fedora-${DIB_RELEASE}.initrd \
                                        | grep id |  tr -d '| ' | cut --bytes=3-57`
        BASE_ID=`glance image-create --name ${NAME} \
                                        --os-distro fedora \
                                        --visibility public \
                                        --disk-format=qcow2 \
                                        --container-format=bare \
                                        --property kernel_id=$KERNEL_ID \
                                        --property ramdisk_id=$RAMDISK_ID \
                                        --file=fedora-${DIB_RELEASE}.qcow2 \
                                        | grep -v kernel | grep -v ramdisk \
                                        | grep id | tr -d '| ' | cut --bytes=3-57`
    else
        BASE_ID=`glance image-create --name ${NAME} \
                                        --os-distro fedora \
                                        --visibility public \
                                        --disk-format=qcow2 \
                                        --container-format=bare \
                                        --file=fedora-${DIB_RELEASE}.qcow2 \
                                        | grep -v kernel | grep -v ramdisk \
                                        | grep id | tr -d '| ' | cut --bytes=3-57`
    fi
fi
