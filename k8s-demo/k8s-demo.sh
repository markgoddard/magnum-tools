#!/bin/bash -e

# Script demoing the use of a kubernetes cluster which has been deployed
# via OpenStack magnum.

if [[ -z $KUBECONFIG ]]; then
    OPENRC_FILE="${OPENRC_FILE:-openrc.sh}"
    VENV="${VENV:-venv}"
    CLUSTER="${CLUSTER:-k8s-fedora-coreos-32}"
fi
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

if ! which kubectl &>/dev/null; then
    mkdir -p k8s-demo
    pushd k8s-demo
    announce "Downloading kubectl client"
    run curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x kubectl
    export PATH=$(pwd):${PATH}
    pause
    popd
fi

if [[ -z $KUBECONFIG ]]; then
    mkdir -p k8s-demo
    pushd k8s-demo
    announce "Getting cluster configuration from magnum API"
    source "${VENV}/bin/activate"
    source "${OPENRC_FILE}"
    run openstack coe cluster config ${CLUSTER} > k8s-env
    deactivate
    ls -l
    pause
    announce "Display dowloaded cluster configuration environment"
    run cat $KUBECONFIG
    source $KUBECONFIG
    pause
    popd
fi

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
pods=$(kubectl get pods -l job-name=inception-client --output=jsonpath={.items..metadata.name})
for pod in $pods; do
    run kubectl logs $pod
    pause
done
