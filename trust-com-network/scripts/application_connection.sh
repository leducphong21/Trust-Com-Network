#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

function app_one_line_pem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function app_json_ccp {
  local ORG=$1
  local PP=$(one_line_pem $2)
  local CP=$(one_line_pem $3)
  local OP=$(one_line_pem $4)
  sed -e "s/\${ORG}/$ORG/" \
      -e "s#\${PEERPEM}#$PP#" \
      -e "s#\${CAPEM}#$CP#" \
      -e "s#\${NS}#${NS}#" \
      -e "s#\${ORDERERPEM}#${OP}#" \
      -e "s#\${ORDERER}}#$ORDERER_NAME#" \
      scripts/ccp-template.json
}

function app_id {
  local MSP=$1
  local CERT=$(one_line_pem $2)
  local PK=$(one_line_pem $3)

  sed -e "s#\${CERTIFICATE}#$CERT#" \
      -e "s#\${PRIVATE_KEY}#$PK#" \
      -e "s#\${MSPID}#$MSP#" \
      scripts/appuser.id.template
}

function construct_application() {
  push_fn "Constructing application connection profiles"

  ENROLLMENT_DIR=${TEMP_DIR}/enrollments
  CHANNEL_MSP_DIR=${TEMP_DIR}/${CHANNEL_NAME}/channel-msp

  mkdir -p build/application/wallet
  mkdir -p build/application/gateways

  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      local peer_pem=$CHANNEL_MSP_DIR/peerOrganizations/${ORG}/msp/tlscacerts/tlsca-signcert.pem
      local ca_pem=$CHANNEL_MSP_DIR/peerOrganizations/${ORG}/msp/cacerts/ca-signcert.pem
      local orderer_pem=$CHANNEL_MSP_DIR/ordererOrganizations/${ORDERER_NAME}/msp/tlscacerts/tlsca-signcert.pem

      echo "$(app_json_ccp ${ORG} $peer_pem $ca_pem $orderer_pem)" > build/application/gateways/${ORG}_ccp.json

      local cert=$ENROLLMENT_DIR/${ORG}/users/${ORG}admin/msp/signcerts/cert.pem
      local pk=$ENROLLMENT_DIR/${ORG}/users/${ORG}admin/msp/keystore/key.pem

      echo "$(app_id ${ORG}MSP $cert $pk)" > build/application/wallet/appuser_${ORG}.id

    done
  done
  
  pop_fn

}


function application_connection() {

 construct_application

}