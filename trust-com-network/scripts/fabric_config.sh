#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

function init_namespace() {
  local namespaces=$(echo "$NS" | xargs -n1 | sort -u)
  for ns in $namespaces; do
    push_fn "Creating namespace \"$ns\""
    kubectl create namespace $ns || true
    pop_fn
  done
}

function delete_namespace() {
  local namespaces=$(echo "$NS" | xargs -n1 | sort -u)
  for ns in $namespaces; do
    push_fn "Deleting namespace \"$ns\""
    kubectl delete namespace $ns || true
    pop_fn
  done
}

function init_storage_volumes() {
  push_fn "Provisioning volume storage"

  # Both KIND and k3s use the Rancher local-path provider.  In KIND, this is installed
  # as the 'standard' storage class, and in Rancher as the 'local-path' storage class.
  if [ "${CLUSTER_RUNTIME}" == "kind" ]; then
    export STORAGE_CLASS="standard"
  elif [ "${CLUSTER_RUNTIME}" == "aws" ]; then
    export STORAGE_CLASS="gp2"

  else
    echo "Unknown CLUSTER_RUNTIME ${CLUSTER_RUNTIME}"
    exit 1
  fi

  cat kube/pvc-fabric-${ORDERER_NAME}.yaml | envsubst | kubectl -n $NS create -f - || true
  
  for ORG in ${ORG_NAMES}; do
    cat kube/pvc-fabric-${ORG}.yaml | envsubst | kubectl -n $NS create -f - || true
  done

  pop_fn
}

function load_org_config() {
  local org_name=$1
  push_fn "Creating fabric config maps" ${org_name}

  kubectl -n $NS delete configmap ${org_name}-config || true
  kubectl -n $NS create configmap ${org_name}-config --from-file=config/${org_name}

  pop_fn
}

function apply_k8s_builder_roles() {
  push_fn "Applying k8s chaincode builder roles"

  apply_template kube/fabric-builder-role.yaml $NS
  apply_template kube/fabric-builder-rolebinding.yaml $NS

  pop_fn
}

function apply_k8s_builders() {
  push_fn "Installing k8s chaincode builders"

  apply_template kube/org1/org1-install-k8s-builder.yaml $NS

  kubectl -n $NS wait --for=condition=complete --timeout=60s job/org1-install-k8s-builder

  pop_fn
}