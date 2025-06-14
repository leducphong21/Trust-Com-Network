#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# chaincode "group" commands.  Like "main" for chaincode sub-command group.
function chaincode_command_group() {
  #set -x

  COMMAND=$1
  shift

  if [ "${COMMAND}" == "deploy" ]; then
    log "Deploying chaincode"
    deploy_chaincode $@
    log "🏁 - Chaincode is ready."

  elif [ "${COMMAND}" == "activate" ]; then
    log "Activating chaincode"
    activate_chaincode $@
    log "🏁 - Chaincode is ready."

  elif [ "${COMMAND}" == "package" ]; then
    log "Packaging chaincode"
    package_chaincode $@
    log "🏁 - Chaincode package is ready."

  elif [ "${COMMAND}" == "id" ]; then
    set_chaincode_id $@
    log $CHAINCODE_ID

  elif [ "${COMMAND}" == "launch" ]; then
    log "Launching chaincode services"
    launch_chaincode $@
    log "🏁 - Chaincode services are ready"

  elif [ "${COMMAND}" == "install" ]; then
    log "Installing chaincode for bank-org"
    install_chaincode $@
    log "🏁 - Chaincode is installed"

  elif [ "${COMMAND}" == "approve" ]; then
    log "Approving chaincode for bank-org"
    approve_chaincode $@
    log "🏁 - Chaincode is approved"

  elif [ "${COMMAND}" == "commit" ]; then
    log "Committing chaincode for bank-org"
    commit_chaincode $@
    log "🏁 - Chaincode is committed"

  elif [ "${COMMAND}" == "invoke" ]; then
    invoke_chaincode $@ 2>> ${LOG_FILE}

  elif [ "${COMMAND}" == "query" ]; then
    query_chaincode $@ >> ${LOG_FILE}

  elif [ "${COMMAND}" == "metadata" ]; then
    query_chaincode_metadata $@ >> ${LOG_FILE}

  else
    print_help
    exit 1
  fi
}

# Convenience routine to "do everything" required to bring up a sample CC.
function deploy_chaincode() {
  local cc_name=$1
  local cc_label=$1
  local cc_folder=$(absolute_path $2)
  local temp_folder=$(mktemp -d)
  local cc_package=${temp_folder}/${cc_name}.tgz

  # Tăng sequence một lần cho toàn bộ quá trình deploy
  local sequence=$(get_next_sequence)
  
  prepare_chaincode_image ${cc_folder} ${cc_name}
  package_chaincode       ${cc_name} ${cc_label} ${cc_package}

  if [ "${CHAINCODE_BUILDER}" == "ccaas" ]; then
    set_chaincode_id      ${cc_package}
    launch_chaincode      ${cc_name} ${CHAINCODE_ID} ${CHAINCODE_IMAGE}
  fi

  activate_chaincode      ${cc_name} ${cc_package} ${sequence}
}

# Prepare a chaincode image for use in a builder package.
# Sets the CHAINCODE_IMAGE environment variable
function prepare_chaincode_image() {
  local cc_folder=$1
  local cc_name=$2

  build_chaincode_image ${cc_folder} ${cc_name}

  if [ "${CLUSTER_RUNTIME}" == "k3s" ]; then
    # For rancher / k3s runtimes, bypass the local container registry and load images directly from the image cache.
    export CHAINCODE_IMAGE=${cc_name}
  else
    # For KIND and k8s-builder environments, publish the image to a local docker registry
    export CHAINCODE_IMAGE=localhost:${LOCAL_REGISTRY_PORT}/${cc_name}
    publish_chaincode_image ${cc_name} ${CHAINCODE_IMAGE}
  fi
}

function build_chaincode_image() {
  local cc_folder=$1
  local cc_name=$2

  push_fn "Building chaincode image ${cc_name}"

  $CONTAINER_CLI build ${CONTAINER_NAMESPACE} -t ${cc_name} ${cc_folder}

  pop_fn
}

# tag a docker image with a new name and publish to a remote container registry
function publish_chaincode_image() {
  local cc_name=$1
  local cc_url=$2
  push_fn "Publishing chaincode image ${cc_url}"

  ${CONTAINER_CLI} tag  ${cc_name} ${cc_url}
  ${CONTAINER_CLI} push ${cc_url}

  pop_fn
}

# Convenience routine to "do everything other than package and launch" a sample CC.
# When debugging a chaincode server, the process must be launched prior to completing
# the chaincode lifecycle at the peer.  This routine provides a route for packaging
# and installing the chaincode out of band, and a single target to complete the peer
# chaincode lifecycle.
function activate_chaincode() {
  local cc_name=$1
  local cc_package=$2
  local sequence=$3  # Nhận sequence từ deploy_chaincode

  set_chaincode_id    ${cc_package}
  install_chaincode   ${cc_package}
  approve_chaincode   ${cc_name} ${CHAINCODE_ID} ${sequence}
  commit_chaincode    ${cc_name} ${sequence}
}

function query_chaincode() {
  local cc_name=$1
  shift

  set -x

  export_peer_context bank-org peer1

  peer chaincode query \
    -n  $cc_name \
    -C  $CHANNEL_NAME \
    -c  $@ \
    #${QUERY_EXTRA_ARGS}
}

function query_chaincode_metadata() {
  local cc_name=$1
  shift

  set -x
  local args='{"Args":["org.hyperledger.fabric:GetMetadata"]}'

  log ''
  log 'Bank-org-Peer1:'
  export_peer_context bank-org peer1
  peer chaincode query -n $cc_name -C $CHANNEL_NAME -c $args

  log ''
  log 'Bank-org-Peer2:'
  export_peer_context bank-org peer2
  peer chaincode query -n $cc_name -C $CHANNEL_NAME -c $args
}

function invoke_chaincode() {
  local cc_name=$1
  shift

  export_peer_context bank peer1

  peer chaincode invoke \
    -n              $cc_name \
    -C              $CHANNEL_NAME \
    -c              $@ \
    --orderer       orderer-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --connTimeout   ${ORDERER_TIMEOUT} \
    --tls --cafile  ${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/ordererOrganizations/orderer/orderers/orderer-orderer1/tls/signcerts/tls-cert.pem \
    #${INVOKE_EXTRA_ARGS}

  sleep 2
}

function package_chaincode() {

  if [ "${CHAINCODE_BUILDER}" == "k8s" ]; then
    package_k8s_chaincode $@

  elif [ "${CHAINCODE_BUILDER}" == "ccaas" ]; then
    package_ccaas_chaincode $@

  else
    log "Unknown CHAINCODE_BUILDER ${CHAINCODE_BUILDER}"
    exit 1
  fi
}

# The k8s builder expects EXACTLY an IMMUTABLE image digest referencing a SPECIFIC image layer at a container registry.
function package_k8s_chaincode() {
  local cc_name=$1
  local cc_label=$2
  local cc_archive=$3

  local cc_folder=$(dirname $cc_archive)
  local archive_name=$(basename $cc_archive)

  push_fn "Packaging k8s chaincode ${cc_archive}"

  mkdir -p ${cc_folder}

  # Find the docker image digest associated with the image at the container registry
  local cc_digest=$(${CONTAINER_CLI} inspect --format='{{index .RepoDigests 0}}' ${CHAINCODE_IMAGE} | cut -d'@' -f2)

  cat << IMAGEJSON-EOF > ${cc_folder}/image.json
{
  "name": "${CHAINCODE_IMAGE}",
  "digest": "${cc_digest}"
}
IMAGEJSON-EOF

  cat << METADATAJSON-EOF > ${cc_folder}/metadata.json
{
    "type": "k8s",
    "label": "${cc_label}"
}
METADATAJSON-EOF

  tar -C ${cc_folder} -zcf ${cc_folder}/code.tar.gz image.json
  tar -C ${cc_folder} -zcf ${cc_archive} code.tar.gz metadata.json

  rm ${cc_folder}/code.tar.gz

  pop_fn
}

function package_ccaas_chaincode() {
  local cc_name=$1
  local cc_label=$2
  local cc_archive=$3

  local cc_folder=$(dirname $cc_archive)
  local archive_name=$(basename $cc_archive)

  push_fn "Packaging ccaas chaincode ${cc_label}"

  mkdir -p ${cc_folder}

  # Allow the user to override the service URL for the endpoint.  This allows, for instance,
  # local debugging at the 'host.docker.internal' DNS alias.
  local cc_default_address="{{.peername}}-ccaas-${cc_name}:9999"
  local cc_address=${TEST_NETWORK_CHAINCODE_ADDRESS:-$cc_default_address}

  cat << EOF > ${cc_folder}/connection.json
{
  "address": "${cc_address}",
  "dial_timeout": "10s",
  "tls_required": false
}
EOF

  cat << EOF > ${cc_folder}/metadata.json
{
  "type": "ccaas",
  "label": "${cc_label}"
}
EOF

  tar -C ${cc_folder} -zcf ${cc_folder}/code.tar.gz connection.json
  tar -C ${cc_folder} -zcf ${cc_archive} code.tar.gz metadata.json

  rm ${cc_folder}/code.tar.gz

  pop_fn
}

function launch_chaincode_service() {
  local org=$1
  local peer=$2
  local cc_name=$3
  local cc_id=$4
  local cc_image=$5
  push_fn "Launching chaincode container \"${cc_image}\""

  # The chaincode endpoint needs to have the generated chaincode ID available in the environment.
  # This could be from a config map, a secret, or by directly editing the deployment spec.  Here we'll keep
  # things simple by using sed to substitute script variables into a yaml template.
  cat kube/${org}/${org}-cc-template.yaml \
    | sed 's,{{CHAINCODE_NAME}},'${cc_name}',g' \
    | sed 's,{{CHAINCODE_ID}},'${cc_id}',g' \
    | sed 's,{{CHAINCODE_IMAGE}},'${cc_image}',g' \
    | sed 's,{{PEER_NAME}},'${peer}',g' \
    | exec kubectl -n $NS apply -f -

  kubectl -n $NS rollout status deploy/${org}${peer}-ccaas-${cc_name}

  pop_fn
}

function launch_chaincode() {
  local cc_name=$1
  local cc_id=$2
  local cc_image=$3

  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      launch_chaincode_service ${ORG} peer${i} ${cc_name} ${cc_id} ${cc_image}
    done
  done

}

function install_chaincode_for() {
  local org=$1
  local peer=$2
  local cc_package=$3
  push_fn "Installing chaincode for org ${org} peer ${peer}"

  export_peer_context $org $peer

  peer lifecycle chaincode install $cc_package #${INSTALL_EXTRA_ARGS}

  pop_fn
}

# Package and install the chaincode, but do not activate.
function install_chaincode() {
  local org=bank-org
  local cc_package=$1

  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      install_chaincode_for ${ORG} peer${i} ${cc_package}
    done
  done
  
}

# approve the chaincode package for an org and assign a name
function approve_chaincode() {
  local cc_name=$1
  local cc_id=$2
  local sequence=$3  # Nhận sequence từ caller
  
  for ORG in ${ORG_NAMES}; do
    local peer=peer1
    push_fn "Approving chaincode ${cc_name} with ID ${cc_id} using sequence ${sequence}"

    export_peer_context $ORG $peer

    peer lifecycle \
      chaincode approveformyorg \
      --channelID     ${CHANNEL_NAME} \
      --name          ${cc_name} \
      --version       1 \
      --package-id    ${cc_id} \
      --sequence      ${sequence} \
      --orderer       ${ORDERER_NAME}-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
      --connTimeout   ${ORDERER_TIMEOUT} \
      --tls --cafile  ${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/ordererOrganizations/orderer/orderers/orderer-orderer1/tls/signcerts/tls-cert.pem \
      #${APPROVE_EXTRA_ARGS}
  done
  
  pop_fn
}

# commit the named chaincode for an org
function commit_chaincode() {
  local cc_name=$1
  local sequence=$2  # Nhận sequence từ caller
  
  local org=$(echo "$ORG_NAMES" | awk '{print $1}')
  local peer=peer1
  push_fn "Committing chaincode ${cc_name} using sequence ${sequence}"

  export_peer_context $org $peer

  peer lifecycle \
    chaincode commit \
    --channelID     ${CHANNEL_NAME} \
    --name          ${cc_name} \
    --version       1 \
    --sequence      ${sequence} \
    --orderer       ${ORDERER_NAME}-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --connTimeout   ${ORDERER_TIMEOUT} \
    --tls --cafile  ${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/ordererOrganizations/orderer/orderers/orderer-orderer1/tls/signcerts/tls-cert.pem \
    #${COMMIT_EXTRA_ARGS}

  pop_fn
}

function set_chaincode_id() {
  local cc_package=$1

  cc_sha256=$(shasum -a 256 ${cc_package} | tr -s ' ' | cut -d ' ' -f 1)
  cc_label=$(tar zxfO ${cc_package} metadata.json | jq -r '.label')

  CHAINCODE_ID=${cc_label}:${cc_sha256}
}

get_next_sequence() {
  local sequence_file="${TEMP_DIR}/sequence.txt"
  
  if [ ! -f "$sequence_file" ]; then
    echo 0 > "$sequence_file"
  fi
  
  local current_sequence=$(cat "$sequence_file")
  local next_sequence=$((current_sequence + 1))
  echo "$next_sequence" > "$sequence_file"
  
  echo "$next_sequence"
}

