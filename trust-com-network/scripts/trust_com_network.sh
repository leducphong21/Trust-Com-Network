#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

function launch_orderers() {
  local index=$1
  push_fn "Launching orderer${index}"

  apply_template kube/${ORDERER_NAME}/${ORDERER_NAME}-orderer${index}.yaml $NS
  kubectl -n $NS rollout status deploy/${ORDERER_NAME}-orderer${index}

  pop_fn
}

function launch_peers() {
  local org_name=$1
  local peer_index=$2
  push_fn "Launching ${org_name} peer${peer_index}"

  apply_template kube/${org_name}/${org_name}-peer${peer_index}.yaml $NS
  kubectl -n $NS rollout status deploy/${org_name}-peer${peer_index}

  pop_fn
}

# Each network node needs a registration, enrollment, and MSP config.yaml
function create_node_local_MSP() {
  local node_type=$1
  local org=$2
  local node=$3
  local csr_hosts=$4
  local ns=$5
  local id_name=${org}-${node}
  local id_secret=${node_type}pw
  local ca_name=${org}-ca

  # Register the node admin
  rc=0
  fabric-ca-client  register \
    --id.name       ${id_name} \
    --id.secret     ${id_secret} \
    --id.type       ${node_type} \
    --url           https://${ca_name}.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls.certfiles $TEMP_DIR/cas/${ca_name}/tlsca-cert.pem \
    --mspdir        $TEMP_DIR/enrollments/${org}/users/${RCAADMIN_USER}/msp \
    || rc=$?        # trap error code from registration without exiting the network driver script"

  if [ $rc -eq 1 ]; then
    echo "CA admin was (probably) previously registered - continuing"
  fi

  # Enroll the node admin user from within k8s.  This will leave the certificates available on a volume share in the
  # cluster for access by the nodes when launching in a container.
  cat <<EOF | kubectl -n ${ns} exec deploy/${ca_name} -i -- /bin/sh

  set -x
  export FABRIC_CA_CLIENT_HOME=/var/hyperledger/fabric-ca-client
  export FABRIC_CA_CLIENT_TLS_CERTFILES=/var/hyperledger/fabric/config/tls/ca.crt

  fabric-ca-client enroll \
    --url https://${id_name}:${id_secret}@${ca_name} \
    --csr.hosts ${csr_hosts} \
    --mspdir /var/hyperledger/fabric/organizations/${node_type}Organizations/${org}.example.com/${node_type}s/${id_name}.${org}.example.com/msp

  # Create local MSP config.yaml
  echo "NodeOUs:
    Enable: true
    ClientOUIdentifier:
      Certificate: cacerts/${org}-ca.pem
      OrganizationalUnitIdentifier: client
    PeerOUIdentifier:
      Certificate: cacerts/${org}-ca.pem
      OrganizationalUnitIdentifier: peer
    AdminOUIdentifier:
      Certificate: cacerts/${org}-ca.pem
      OrganizationalUnitIdentifier: admin
    OrdererOUIdentifier:
      Certificate: cacerts/${org}-ca.pem
      OrganizationalUnitIdentifier: orderer" > /var/hyperledger/fabric/organizations/${node_type}Organizations/${org}.example.com/${node_type}s/${id_name}.${org}.example.com/msp/config.yaml
EOF
}

function create_orderer_local_MSP() {
  local org=$1
  local orderer=$2
  local csr_hosts=${org}-${orderer}

  create_node_local_MSP orderer $org $orderer $csr_hosts $NS
}

function create_peer_local_MSP() {
  local org=$1
  local peer=$2
  local ns=$3
  local csr_hosts=localhost,${org}-${peer},${org}-peer-gateway-svc

  create_node_local_MSP peer $org $peer $csr_hosts ${ns}
}

function create_local_MSP() {
  local org_name=$1
  local peer_index=$2
  push_fn "Creating local node MSP ${org_name} peer${peer_index}"

  create_peer_local_MSP ${org_name} peer${peer_index} $NS

  pop_fn
}

function create_local_MSP_orderer() {
  local index=$1
  push_fn "Creating local node MSP ${ORDERER_NAME}${index}"

  create_orderer_local_MSP ${ORDERER_NAME} orderer${index}

  pop_fn
}

function add_peer() {
  local org=$1
  local index=$2
  ORG_DIR="kube/${org}"
  # generate peer yaml
  sed \
    -e "s/{{ORG_NAME}}/${org}/g" \
    -e "s/{{PEER_NUM}}/${index}/g" \
    templates/kube/org/peer-template.yaml \
    > "${ORG_DIR}/${org}-peer${index}.yaml"

  # create local msp
  create_local_MSP ${org} ${index}

  # luanch peer
  launch_peers ${org} ${index}
}

function network_up() {

  # Kube config
  init_namespace
  init_storage_volumes
  
  if [[ -n "$ENV_NUM_ORDERERS" && "$ENV_NUM_ORDERERS" =~ ^[0-9]+$ && "$ENV_NUM_ORDERERS" -gt 0 ]]; then
    load_org_config "$ORDERER_NAME"
  fi
  for ORG in ${ORG_NAMES}; do
    load_org_config ${ORG}
  done

  # Service account permissions for the k8s builder
  if [ "${CHAINCODE_BUILDER}" == "k8s" ]; then
    apply_k8s_builder_roles
    apply_k8s_builders
  fi

  # Network TLS CAs
  if [[ -n "$ENV_NUM_ORDERERS" && "$ENV_NUM_ORDERERS" =~ ^[0-9]+$ && "$ENV_NUM_ORDERERS" -gt 0 ]]; then
    init_tls_cert_issuers_org ${ORDERER_NAME}
  fi
  for ORG in ${ORG_NAMES}; do
    init_tls_cert_issuers_org ${ORG}
  done



  # Network ECert CAs
  if [[ -n "$ENV_NUM_ORDERERS" && "$ENV_NUM_ORDERERS" =~ ^[0-9]+$ && "$ENV_NUM_ORDERERS" -gt 0 ]]; then
    launch_ECert_CAs_org ${ORDERER_NAME}
  fi
  for ORG in ${ORG_NAMES}; do
    launch_ECert_CAs_org ${ORG}
  done



  # enroll orderer cert
  if [[ -n "$ENV_NUM_ORDERERS" && "$ENV_NUM_ORDERERS" =~ ^[0-9]+$ && "$ENV_NUM_ORDERERS" -gt 0 ]]; then
    enroll_bootstrap_ECert_CA_users ${ORDERER_NAME}
  fi
  for ORG in ${ORG_NAMES}; do
    enroll_bootstrap_ECert_CA_users ${ORG}
  done



  # Trust Com Network
  if [[ -n "$ENV_NUM_ORDERERS" && "$ENV_NUM_ORDERERS" =~ ^[0-9]+$ && "$ENV_NUM_ORDERERS" -gt 0 ]]; then
    for ((i=1; i<=NUM_ORDERERS; i++)); do
      create_local_MSP_orderer ${i}
    done
  fi
 

  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      create_local_MSP ${ORG} ${i}
    done
  done
  
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    launch_orderers ${i}
  done
  
  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      launch_peers ${ORG} ${i}
    done
  done

}

function stop_services() {
  push_fn "Stopping Fabric services"
  for ns in $NS; do
    kubectl -n $ns delete ingress --all
    kubectl -n $ns delete deployment --all
    kubectl -n $ns delete pod --all
    kubectl -n $ns delete service --all
    kubectl -n $ns delete configmap --all
    kubectl -n $ns delete cert --all
    kubectl -n $ns delete issuer --all
    kubectl -n $ns delete secret --all
  done

  pop_fn
}

function scrub_org_volumes() {
  push_fn "Scrubbing Fabric volumes"
  local namespace_variable=${NS}
  for org in ${ORG_NAMES}; do
    # clean job to make this function can be rerun
    kubectl -n ${namespace_variable} delete jobs --all

    # scrub all pv contents
    kubectl -n ${namespace_variable} create -f kube/${org}/${org}-job-scrub-fabric-volumes.yaml
    kubectl -n ${namespace_variable} wait --for=condition=complete --timeout=60s job/job-scrub-fabric-volumes
    kubectl -n ${namespace_variable} delete jobs --all
  done

  # clean job to make this function can be rerun
  kubectl -n ${namespace_variable} delete jobs --all

  # scrub all pv contents
  kubectl -n ${namespace_variable} create -f kube/${ORDERER_NAME}/${ORDERER_NAME}-job-scrub-fabric-volumes.yaml
  kubectl -n ${namespace_variable} wait --for=condition=complete --timeout=60s job/job-scrub-fabric-volumes
  kubectl -n ${namespace_variable} delete jobs --all

  pop_fn
}

function network_down() {

  set +e
  for ns in $NS; do
    kubectl get namespace $ns > /dev/null
    if [[ $? -ne 0 ]]; then
      echo "No namespace $ns found - nothing to do."
      return
    fi
  done
  set -e

  stop_services
  scrub_org_volumes

  delete_namespace

  rm -rf $TEMP_DIR
  rm -rf $PWD/kube
  rm -rf $PWD/config
}
