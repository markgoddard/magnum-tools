#!/bin/bash -e

# Script demoing the use of a kubernetes cluster which has been deployed
# via OpenStack magnum.

# These IPs should be set to the floating IP addresses of the Swarm nodes.
OPENRC_FILE="${OPENRC_FILE:-/ilab-home/hpcgodd1/mark-openrc.sh}"
VENV="${VENV:-/ilab-home/hpcgodd1/os-venv}"
CLUSTER="${CLUSTER:-mark-k8s-fedora-25}"
PAUSE=${PAUSE:-1}
SLEEP=${SLEEP:-20}

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

announce "Demo: Kubernetes on OpenStack magnum!"
announce
announce "We will create a service for classifying images using the Inception"
announce "neural network model running on tensorflow pre-trained using the"
announce "ImageNet dataset. We will use this service to classify some pictures"
announce "of cats."
if [[ ${PAUSE} = 1 ]]; then
    read
fi

mkdir k8s-demo
cd k8s-demo

announce "Downloading kubectl client"
run curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl
export PATH=$(pwd):${PATH}
pause

announce "Getting cluster configuration from magnum API"
source "${VENV}/bin/activate"
source "${OPENRC_FILE}"
run magnum cluster-config ${CLUSTER} > k8s-env
deactivate
ls -l
pause

announce "Display dowloaded cluster configuration environment"
run cat k8s-env
source k8s-env
cd -
pause

announce "Cleaning up old state"
run kubectl delete -f inception-client-job.yml || true
run sleep ${SLEEP}
run kubectl delete -f inception-service.yml || true
run sleep ${SLEEP}
run kubectl delete -f inception-deployment.yml || true
run sleep ${SLEEP}

announce "Creating a deployment with 3 inception pods"
run cat inception-deployment.yml
pause
run kubectl create -f inception-deployment.yml
run sleep ${SLEEP}
run kubectl get deployments
run kubectl get pods -l k8s-app=inception-deployment -o wide
pause

announce "Exposing a inception as a service"
run cat inception-service.yml
pause
run kubectl create -f inception-service.yml
run sleep ${SLEEP}
run kubectl get services -l k8s-app=inception-deployment
pause

announce "Scaling up to 4 replicas"
run kubectl scale deployments/inception-deployment --replicas=4
run sleep ${SLEEP}
run kubectl get deployments
run kubectl get pods -l k8s-app=inception-deployment -o wide
pause

announce "Creating a job with 3 parallel clients"
run cat inception-client-job.yml
pause
run kubectl create -f inception-client-job.yml
run sleep ${SLEEP}
run kubectl get jobs
pause

announce "Viewing job results"
pods=$(kubectl get pods  --show-all -l job-name=inception-client --output=jsonpath={.items..metadata.name})
for pod in $pods; do
    run kubectl log $pod
    pause
done
