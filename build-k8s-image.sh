#!/bin/bash -e

# Build and/or register an image for use with OpenStack magnum using kubernetes
# on fedora 25 on baremetal.

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
export ELEMENTS_PATH=magnum/magnum/drivers/k8s_fedora_ironic_v1/image:magnum/magnum/drivers/common/image

# The following is required for --visibility and --os-distro arguments.
export OS_IMAGE_API_VERSION=2

# Supports 'fedora' and 'fedora-atomic'.
OS_DISTRO=${OS_DISTRO:-fedora}
case $OS_DISTRO in
    fedora | fedora-atomic)
        DIB_RELEASE=${DIB_RELEASE:-25}
        ;;
    *)
        echo "Unsupported OS_DISTRO: $OS_DISTRO"
        ;;
esac
export DIB_RELEASE
NAME=${NAME:-k8s-${OS_DISTRO}-${DIB_RELEASE}}
FILENAME=${FILENAME:-$NAME}
USE_WHOLE_DISK_IMAGE=${USE_WHOLE_DISK_IMAGE:-0}

if [[ $BUILD -eq 1 ]]; then
    echo "Building image"
    ELEMENTS="dhcp-all-interfaces \
enable-serial-console \
selinux-permissive"

    if [[ $USE_WHOLE_DISK_IMAGE -eq 0 ]]; then
        ELEMENTS="$ELEMENTS baremetal grub2"
    else
        ELEMENTS="$ELEMENTS vm"
    fi

    # Use dracut-regenerate if possible, but it was only added recently.
    if [[ -f dib-venv/lib/python2.7/site-packages/diskimage_builder/elements/dracut-regenerate ]]; then
        ELEMENTS="$ELEMENTS dracut-regenerate"
    else
        ELEMENTS="$ELEMENTS dracut-network"
    fi

    case $OS_DISTRO in
        fedora)
            ELEMENTS="$ELEMENTS fedora kubernetes"
            ;;
        fedora-atomic)
            ELEMENTS="$ELEMENTS fedora-atomic"
            export DIB_IMAGE_SIZE=2.5
            # Without these the select-boot-kernel-initrd element fails as the
            # ramdisk and kernel are not in /boot. This element is a dependency
            # of dracut-network/dracut-regenerate.
            export DIB_BAREMETAL_KERNEL_PATTERN='ostree/fedora-atomic-*/vmlinuz*'
            export DIB_BAREMETAL_INITRD_PATTERN='ostree/fedora-atomic-*/initramfs-*'
            ;;
    esac

    disk-image-create $ELEMENTS -o ${FILENAME}.qcow2 -x
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
                                        --os-distro ${OS_DISTRO} \
                                        --visibility public \
                                        --disk-format=qcow2 \
                                        --container-format=bare \
                                        --file=${FILENAME}.qcow2 \
                                        | grep -v kernel | grep -v ramdisk \
                                        | grep id | tr -d '| ' | cut --bytes=3-57`
    fi
    echo "Registered images"
    echo "Kernel: $KERNEL_ID"
    echo "Ramdisk: $RAMDISK_ID"
    echo "Image: $BASE_ID"
fi
