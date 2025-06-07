#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

function channel_command_group() {
  # set -x

  COMMAND=$1
  shift

  if [ "${COMMAND}" == "create-org-admin" ]; then
    log "Creating org admin \"${CHANNEL_NAME}\":"
    create_org_admin
    log "🏁 - Org admin is ready."

  elif [ "${COMMAND}" == "create-channel-msp" ]; then
    log "Creating channel MSP \"${CHANNEL_NAME}\":"
    create_channel_MSP
    log "🏁 - Channel MSP is ready."

  elif [ "${COMMAND}" == "create" ]; then
    log "Creating channel \"${CHANNEL_NAME}\":"
    channel_up
    log "🏁 - Channel is ready."

  elif [ "${COMMAND}" == "join-orderer" ]; then
    local orderer=$1
    log "Joining ${orderer} to \"${CHANNEL_NAME}\":"
    join_channel_orderer "${ORDERER_NAME}" "${orderer}"
    log "🏁 - Joining orderer complete."

  elif [ "${COMMAND}" == "join-peer" ]; then
    local org=$1
    local peer=$2
    log "Joining ${peer} of ${org} to \"${CHANNEL_NAME}\":"
    join_channel_peer "${org}" "${peer}"
    log "🏁 - Joining peer complete."

  elif [ "${COMMAND}" == "fetch-config" ]; then
    log "Fetching channel config for \"${CHANNEL_NAME}\":"
    fetch_channel_config
    log "🏁 - Channel config fetched."

  elif [ "${COMMAND}" == "get-modify-config" ]; then
    log "Getting and modifying config for \"${CHANNEL_NAME}\":"
    get-modify-config
    if [ $? -eq 0 ]; then
      log "🏁 - Config fetched and prepared."
    else
      log "Failed to fetch or prepare config."
    fi

  elif [ "${COMMAND}" == "create-config-update-envelope" ]; then
    log "Creating config update envelope for \"${CHANNEL_NAME}\":"
    create-config-update-envelope
    if [ $? -eq 0 ]; then
      log "🏁 - Config update envelope created."
    else
      log "Failed to create config update envelope."
    fi

  elif [ "${COMMAND}" == "sign" ]; then
    local org=$1
    log "Signing config for \"${CHANNEL_NAME}\" with ${org}:"
    sign "${org}" 
    if [ $? -eq 0 ]; then
      log "🏁 - Config signed."
    else
      log "Failed to sign config."
    fi

  elif [ "${COMMAND}" == "update-config" ]; then
    local org=$1
    log "Updating config for \"${CHANNEL_NAME}\" with ${org}:"
    update-config "${org}"
    if [ $? -eq 0 ]; then
      log "🏁 - Config updated."
    else
      log "Failed to update config."
    fi

  else
    print_help
    exit 1
  fi
}

function create_org_admin() {
  register_org_admins
  enroll_org_admins
}


function channel_up() {
  create_genesis_block
  join_channel_orderers
  join_channel_peers
}

function register_org_admins() {
  push_fn "Registering org Admin users"

  register_org_admin ${ORDERER_NAME} ${ORDERER_NAME}admin ${ORDERER_NAME}adminpw
  for ORG in ${ORG_NAMES}; do
    register_org_admin ${ORG} ${ORG}admin ${ORG}adminpw
  done

  pop_fn
}

# Register the org admin user
function register_org_admin() {
  local type=admin
  local org=$1
  local id_name=$2
  local id_secret=$3
  local ca_name=${org}-ca

  echo "Registering org admin $id_name"

  fabric-ca-client  register \
    --id.name       ${id_name} \
    --id.secret     ${id_secret} \
    --id.type       ${type} \
    --url           https://${ca_name}.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls.certfiles $TEMP_DIR/cas/${ca_name}/tlsca-cert.pem \
    --mspdir        $TEMP_DIR/enrollments/${org}/users/${RCAADMIN_USER}/msp \
    --id.attrs      "hf.Registrar.Roles=client,hf.Registrar.Attributes=*,hf.Revoker=true,hf.GenCRL=true,admin=true:ecert,abac.init=true:ecert"
}

function enroll_org_admins() {
  push_fn "Enrolling org Admin users"

  enroll_org_admin orderer  ${ORDERER_NAME} ${ORDERER_NAME}admin ${ORDERER_NAME}adminpw
  for ORG in ${ORG_NAMES}; do
    enroll_org_admin peer     ${ORG} ${ORG}admin ${ORG}adminpw
  done

  pop_fn
}

# Enroll the admin client to the local certificate storage folder.
function enroll_org_admin() {
  local type=$1
  local org=$2
  local username=$3
  local password=$4

  echo "Enrolling $type org admin $username"

  ENROLLMENTS_DIR=${TEMP_DIR}/enrollments
  ORG_ADMIN_DIR=${ENROLLMENTS_DIR}/${org}/users/${username}

  # skip the enrollment if the admin certificate is available.
  if [ -f "${ORG_ADMIN_DIR}/msp/keystore/key.pem" ]; then
    echo "Found an existing admin enrollment at ${ORG_ADMIN_DIR}"
    return
  fi

  # Determine the CA information and TLS certificate
  CA_NAME=${org}-ca
  CA_DIR=${TEMP_DIR}/cas/${CA_NAME}

  CA_AUTH=${username}:${password}
  CA_HOST=${CA_NAME}.${DOMAIN}
  CA_PORT=${NGINX_HTTPS_PORT}
  CA_URL=https://${CA_AUTH}@${CA_HOST}:${CA_PORT}

  # enroll the org admin
  FABRIC_CA_CLIENT_HOME=${ORG_ADMIN_DIR} fabric-ca-client enroll \
    --url ${CA_URL} \
    --tls.certfiles ${CA_DIR}/tlsca-cert.pem

  # Construct an msp config.yaml
  CA_CERT_NAME=${CA_NAME}-$(echo $DOMAIN | tr -s . -)-${CA_PORT}.pem

  create_msp_config_yaml ${CA_NAME} ${CA_CERT_NAME} ${ORG_ADMIN_DIR}/msp

  # private keys are hashed by name, but we only support one enrollment.
  # test-network examples refer to this as "server.key", which is incorrect.
  # This is the private key used to endorse transactions using the admin's
  # public key.
  mv ${ORG_ADMIN_DIR}/msp/keystore/*_sk ${ORG_ADMIN_DIR}/msp/keystore/key.pem
}

# create an enrollment MSP config.yaml
function create_msp_config_yaml() {
  local ca_name=$1
  local ca_cert_name=$2
  local msp_dir=$3
  echo "Creating msp config ${msp_dir}/config.yaml with cert ${ca_cert_name}"

  cat << EOF > ${msp_dir}/config.yaml
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${ca_cert_name}
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${ca_cert_name}
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${ca_cert_name}
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${ca_cert_name}
    OrganizationalUnitIdentifier: orderer
EOF
}

function create_channel_MSP() {
  push_fn "Creating channel MSP"

  create_channel_org_MSP ${ORDERER_NAME} orderer $NS
  for ORG in ${ORG_NAMES}; do
    create_channel_org_MSP ${ORG} peer $NS
  done

  for ((i=1; i<=NUM_ORDERERS; i++)); do
    extract_orderer_cert ${ORDERER_NAME} orderer${i}
  done

  if  [ "${ORDERER_TYPE}" == "bft" ]; then
      extract_orderer_cert org0 orderer4
  fi

  pop_fn
}

function create_channel_org_MSP() {
  local org=$1
  local type=$2
  local ns=$3
  local ca_name=${org}-ca

  ORG_MSP_DIR=${TEMP_DIR}/channel-msp/${type}Organizations/${org}/msp
  mkdir -p ${ORG_MSP_DIR}/cacerts
  mkdir -p ${ORG_MSP_DIR}/tlscacerts

  # extract the CA's signing authority from the CA/cainfo response
  curl -s \
    --cacert ${TEMP_DIR}/cas/${ca_name}/tlsca-cert.pem \
    https://${ca_name}.${DOMAIN}:${NGINX_HTTPS_PORT}/cainfo \
    | jq -r .result.CAChain \
    | base64 -d \
    > ${ORG_MSP_DIR}/cacerts/ca-signcert.pem

  # extract the CA's TLS CA certificate from the cert-manager secret
  kubectl -n $ns get secret ${ca_name}-tls-cert -o json \
    | jq -r .data.\"ca.crt\" \
    | base64 -d \
    > ${ORG_MSP_DIR}/tlscacerts/tlsca-signcert.pem

  # create an MSP config.yaml with the CA's signing certificate
  create_msp_config_yaml ${ca_name} ca-signcert.pem ${ORG_MSP_DIR}
}

# Extract an orderer's signing certificate for inclusion in the channel config block
function extract_orderer_cert() {
  local org=$1
  local orderer=$2
  local ns=$NS

  echo "Extracting cert for $org $orderer"

  ORDERER_TLS_DIR=${TEMP_DIR}/channel-msp/ordererOrganizations/${org}/orderers/${org}-${orderer}/tls
  mkdir -p $ORDERER_TLS_DIR/signcerts

  kubectl -n $ns get secret ${org}-${orderer}-tls-cert -o json \
    | jq -r .data.\"tls.crt\" \
    | base64 -d \
    > ${ORDERER_TLS_DIR}/signcerts/tls-cert.pem

  # For the orderer type is BFT, retrieve the enrollment certificate from the pod
  POD_NAME=$(kubectl -n $ns get pods -l app=${org}-${orderer} -o jsonpath="{.items[0].metadata.name}")
  # - Check if the pod exists before proceeding
  if [ -z "$POD_NAME" ]; then
    fatalln "Error: No Pod found with label app=${org}-${orderer} in namespace $ns"
  fi
  # - Copy the enrollment certificate from the pod to the local machine
  kubectl -n $ns cp ${POD_NAME}:var/hyperledger/fabric/organizations/ordererOrganizations/${org}.example.com/orderers/${org}-${orderer}.${org}.example.com/msp/signcerts/cert.pem ${TEMP_DIR}/channel-msp/ordererOrganizations/${org}/orderers/${org}-${orderer}/cert.pem
}

function create_genesis_block() {
  push_fn "Creating channel genesis block"
  mkdir -p ${TEMP_DIR}/${CHANNEL_NAME}
  # Define the default channel configtx and profile
  local profile="TwoOrgsApplicationGenesis"
  # cat ${PWD}/config/org0/configtx-template.yaml | envsubst > ${TEMP_DIR}/configtx.yaml

  # Overwrite configtx and profile for bft orderer
  if  [ "${ORDERER_TYPE}" == "bft" ]; then
    # cat ${PWD}/config/org0/bft/configtx-template.yaml | envsubst > ${TEMP_DIR}/configtx.yaml
    profile="ChannelUsingBFT"
  fi

  FABRIC_CFG_PATH=${TEMP_DIR} \
    configtxgen \
      -profile      $profile \
      -channelID    $CHANNEL_NAME \
      -outputBlock  ${TEMP_DIR}/${CHANNEL_NAME}/genesis_block.pb

  # configtxgen -inspectBlock ${TEMP_DIR}/genesis_block.pb

  pop_fn
}

function join_channel_orderers() {
  push_fn "Joining orderers to channel ${CHANNEL_NAME}"

  for ((i=1; i<=NUM_ORDERERS; i++)); do
    join_channel_orderer ${ORDERER_NAME} orderer${i}
  done

  # if  [ "${ORDERER_TYPE}" == "bft" ]; then
  #   join_channel_orderer org0 orderer4
  # fi

  # todo: readiness / liveiness equivalent for channel?  Needs a little bit to settle before peers can join.
  sleep 10

  pop_fn
}

# Request from the channel ADMIN api that the orderer joins the target channel
function join_channel_orderer() {
  local org=$1
  local orderer=$2

  # The client certificate presented in this case is the admin user's enrollment key.  This is a stronger assertion
  # of identity than the Docker Compose network, which transmits the orderer node's TLS key pair directly
  osnadmin channel join \
    --orderer-address ${org}-${orderer}-admin.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --ca-file         ${TEMP_DIR}/channel-msp/ordererOrganizations/${org}/orderers/${org}-${orderer}/tls/signcerts/tls-cert.pem \
    --client-cert     ${TEMP_DIR}/enrollments/${org}/users/${org}admin/msp/signcerts/cert.pem \
    --client-key      ${TEMP_DIR}/enrollments/${org}/users/${org}admin/msp/keystore/key.pem \
    --channelID       ${CHANNEL_NAME} \
    --config-block    ${TEMP_DIR}/${CHANNEL_NAME}/genesis_block.pb
}

function join_channel_peers() {
  for ORG in ${ORG_NAMES}; do
  push_fn "Joining ${ORG} peers to channel ${CHANNEL_NAME}"
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      join_channel_peer  ${ORG} peer${i}
    done
  done
}

function join_org_peers() {
  local org=$1
  push_fn "Joining ${org} peers to channel ${CHANNEL_NAME}"

  # Join peers to channel
  join_channel_peer $org peer1
  join_channel_peer $org peer2

  pop_fn
}

function join_channel_peer() {
  local org=$1
  local peer=$2

  export_peer_context $org $peer

  peer channel join \
    --blockpath   ${TEMP_DIR}/${CHANNEL_NAME}/genesis_block.pb \
    --orderer     org0-orderer1.${DOMAIN} \
    --connTimeout ${ORDERER_TIMEOUT} \
    --tls         \
    --cafile      ${TEMP_DIR}/channel-msp/ordererOrganizations/org0/orderers/org0-orderer1/tls/signcerts/tls-cert.pem
}

function fetch_channel_config() {
  # Log the start of fetching channel configuration
  local first_org=$(echo "$ORG_NAMES" | awk '{print $1}')
  push_fn "Fetching channel configuration for ${CHANNEL_NAME}"

  # Set the peer context to bank-org peer1 (organization đầu tiên trong ORG_NAMES)
  export_peer_context ${first_org} peer1

  # Fetch the channel configuration block from the orderer
  peer channel fetch config ${TEMP_DIR}/channel_config.pb \
    -c ${CHANNEL_NAME} \
    --orderer ${ORDERER_NAME}-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls \
    --cafile ${TEMP_DIR}/channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer1/tls/signcerts/tls-cert.pem

  # Decode the protobuf block into JSON format and extract the config
  configtxlator proto_decode --input ${TEMP_DIR}/channel_config.pb --type common.Block | jq .data.data[0].payload.data.config > ${TEMP_DIR}/channel_config.json

  # Log the location where the config is saved
  log "Channel config saved to ${TEMP_DIR}/channel_config.pb (protobuf) and ${TEMP_DIR}/channel_config.json (JSON)"

  # Log the completion of the function
  pop_fn
}


function get-modify-config() {
  local first_org=$(echo "$ORG_NAMES" | awk '{print $1}')
  # Log the start of fetching and preparing channel configuration
  push_fn "Fetching and preparing channel configuration for ${CHANNEL_NAME}"

  # Set the peer context to bank-org peer1
  export_peer_context ${first_org} peer1

  # Fetch the current channel configuration block from the orderer
  peer channel fetch config ${TEMP_DIR}/current_config_block.pb \
    -c ${CHANNEL_NAME} \
    --orderer ${ORDERER_NAME}-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls \
    --cafile ${TEMP_DIR}/channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer1/tls/signcerts/tls-cert.pem

  # Decode the protobuf block into JSON format and extract the config
  configtxlator proto_decode --input ${TEMP_DIR}/current_config_block.pb \
    --type common.Block | jq .data.data[0].payload.data.config > ${TEMP_DIR}/current_config.json

  # Log that the modified_config.json will be created or overwritten
  log "Creating or overwriting modified_config.json with current_config.json"
  
  # Overwrite or create modified_config.json with the current config
  cp -f ${TEMP_DIR}/current_config.json ${TEMP_DIR}/modified_config.json
  if [ $? -ne 0 ]; then
    log "Error: Failed to create or overwrite modified_config.json"
    pop_fn
    return 1
  fi
  
  # Log the location of the new/overwritten file and prompt for editing
  log "modified_config.json created/overwritten at ${TEMP_DIR}/modified_config.json. Please edit it before proceeding."

  # Log the completion of the function
  pop_fn
}


function create-config-update-envelope() {
  # Log the start of creating the configuration update envelope
  push_fn "Creating configuration update envelope for ${CHANNEL_NAME}"

  # Encode the current config JSON into protobuf format
  configtxlator proto_encode --input ${TEMP_DIR}/current_config.json \
    --type common.Config --output ${TEMP_DIR}/current_config.pb
  
  # Encode the modified config JSON into protobuf format
  configtxlator proto_encode --input ${TEMP_DIR}/modified_config.json \
    --type common.Config --output ${TEMP_DIR}/modified_config.pb

  # Compute the difference (delta) between current and modified configs
  configtxlator compute_update --channel_id ${CHANNEL_NAME} \
    --original ${TEMP_DIR}/current_config.pb \
    --updated ${TEMP_DIR}/modified_config.pb \
    --output ${TEMP_DIR}/config_update.pb

  # Decode the delta protobuf into JSON format
  configtxlator proto_decode --input ${TEMP_DIR}/config_update.pb \
    --type common.ConfigUpdate > ${TEMP_DIR}/config_update.json

  # Create an envelope JSON with the config update and channel header
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'", "type":2}},"data":{"config_update":'$(cat ${TEMP_DIR}/config_update.json)'}}}' | jq . > ${TEMP_DIR}/config_update_envelope.json
  
  # Encode the envelope JSON into protobuf format
  configtxlator proto_encode --input ${TEMP_DIR}/config_update_envelope.json \
    --type common.Envelope --output ${TEMP_DIR}/config_update_envelope.pb

  # Log the completion of the function
  pop_fn
}

function sign() {
  local org=$1

  # Debug và log
  push_fn "DEBUG: Entering sign() function with org: ${org},"
  push_fn "Signing configuration envelope for ${CHANNEL_NAME}"

  log "Using organization: ${org}"

  # Set context dựa trên tổ chức và node
  export_peer_context "${org}"  "none"
  export CORE_PEER_MSPCONFIGPATH=${TEMP_DIR}/enrollments/${org}/users/${org}admin/msp

  # Sign the configuration envelope
  peer channel signconfigtx -f ${TEMP_DIR}/config_update_envelope.pb
  if [ $? -ne 0 ]; then
    pop_fn "Error: Failed to sign config envelope with ${org}"
    pop_fn
    return 1
  fi

  pop_fn "Successfully signed config envelope with ${org}"
  pop_fn
}


function update-config() {
   local org=$1
   # Log the start of submitting the configuration update
   log "Submitting channel configuration update for ${CHANNEL_NAME}"
 
   # If an org is provided as an argument, use it directly
   if [ -n "${org}" ]; then
     selected_org="${org}"
     log "Using provided organization: ${selected_org}"
   else
     # Check if running in an interactive terminal
     if [ -t 0 ]; then
       # Display the organization selection menu
       log "Please select an organization to submit the configuration update:"
       log "  1) org1"
       log "  2) org2"
       log -n "Enter your choice (1-2): "
       read choice
 
       # Map the user's choice to an organization
       case $choice in
         1) selected_org="org1" ;;
         2) selected_org="org2" ;;
         *) log "Error: Invalid selection. Please choose a valid option (1-2)."
            pop_fn
            return 1 ;;
       esac
 
       # Log the selected organization
       log "Selected organization: ${selected_org}"
     else
       # Log an error if not in an interactive terminal
       log "Error: No interactive terminal detected. Please provide an organization (e.g., 'update-config org1') or run in an interactive shell."
       pop_fn
       return 1
     fi
   fi
 
   # Check if an organization was selected or provided
   if [ -z "${selected_org}" ]; then
     log "Error: No organization selected or provided"
     pop_fn
     return 1
   fi
 
   # Set the peer context and MSP based on the selected organization
   if [ "${selected_org}" == "org1" ]; then
     export_peer_context org1 peer1
   elif [ "${selected_org}" == "org2" ]; then
     export_peer_context org2 peer1
   else
     log "Error: Unsupported organization: ${selected_org}. Only org1 and org2 are allowed."
     pop_fn
     return 1
   fi
 
   # Set the MSP path for submitting the update
   export CORE_PEER_MSPCONFIGPATH=${TEMP_DIR}/enrollments/${selected_org}/users/${selected_org}admin/msp
   
   # Submit the configuration update to the orderer
   peer channel update \
     -f ${TEMP_DIR}/config_update_envelope.pb \
     -c ${CHANNEL_NAME} \
     --orderer org0-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
     --tls \
     --cafile ${TEMP_DIR}/channel-msp/ordererOrganizations/org0/orderers/org0-orderer1/tls/signcerts/tls-cert.pem
 
   # Check if the update failed
   if [ $? -ne 0 ]; then
     log "Error: Failed to update config with ${selected_org}"
     pop_fn
     return 1
   fi
 
   # Log successful update
   log "Channel configuration for ${CHANNEL_NAME} has been updated successfully"
   pop_fn
 }


function update-config() {
   local org=$1
   # Log the start of submitting the configuration update
   pop_fn "Submitting channel configuration update for ${CHANNEL_NAME}"

  export_peer_context ${org} peer1

 
   # Set the MSP path for submitting the update
   export CORE_PEER_MSPCONFIGPATH=${TEMP_DIR}/enrollments/${org}/users/${org}admin/msp
   
   # Submit the configuration update to the orderer
   peer channel update \
     -f ${TEMP_DIR}/config_update_envelope.pb \
     -c ${CHANNEL_NAME} \
     --orderer ${ORDERER_NAME}-orderer1.${DOMAIN}:${NGINX_HTTPS_PORT} \
     --tls \
     --cafile ${TEMP_DIR}/channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer1/tls/signcerts/tls-cert.pem
 
   # Check if the update failed
   if [ $? -ne 0 ]; then
     log "Error: Failed to update config with ${org}"
     pop_fn
     return 1
   fi
 
   # Log successful update
   pop_fn "Channel configuration for ${CHANNEL_NAME} has been updated successfully"
 }