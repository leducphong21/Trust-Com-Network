#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

function launch_ECert_CAs_org() {
  local org_name=$1
  push_fn "Launching Fabric CAs ${org_name}"

  apply_template kube/${org_name}/${org_name}-ca.yaml $ORG1_NS
  kubectl -n $ORG1_NS rollout status deploy/${org_name}-ca

  # todo: this papers over a nasty bug whereby the CAs are ready, but sporadically refuse connections after a down / up
  sleep 5

  pop_fn
}

# experimental: create TLS CA issuers using cert-manager for each org.
function init_tls_cert_issuers_org() {
  local org_name=$1
  push_fn "Initializing TLS certificate Issuers" ${org_name}

  # Create a self-signing certificate issuer / root TLS certificate for the blockchain.
  # TODO : Bring-Your-Own-Key - allow the network bootstrap to read an optional ECDSA key pair for the TLS trust root CA.
  kubectl -n $ORG0_NS apply -f kube/root-tls-cert-issuer.yaml
  kubectl -n $ORG0_NS wait --timeout=30s --for=condition=Ready issuer/root-tls-cert-issuer

  # Use the self-signing issuer to generate three Issuers, one for each org.
  kubectl -n $ORG1_NS apply -f kube/${org_name}/${org_name}-tls-cert-issuer.yaml
  kubectl -n $ORG1_NS wait --timeout=30s --for=condition=Ready issuer/${org_name}-tls-cert-issuer

  pop_fn
}


function enroll_bootstrap_ECert_CA_user() {
  local org=$1
  local ns=$2

  # Determine the CA information and TLS certificate
  CA_NAME=${org}-ca
  CA_DIR=${TEMP_DIR}/cas/${CA_NAME}
  mkdir -p ${CA_DIR}

  # Read the CA's TLS certificate from the cert-manager CA secret
  echo "retrieving ${CA_NAME} TLS root cert"
  kubectl -n $ns get secret ${CA_NAME}-tls-cert -o json \
    | jq -r .data.\"ca.crt\" \
    | base64 -d \
    > ${CA_DIR}/tlsca-cert.pem

  # Enroll the root CA user
  fabric-ca-client enroll \
    --url https://${RCAADMIN_USER}:${RCAADMIN_PASS}@${CA_NAME}.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls.certfiles $TEMP_DIR/cas/${CA_NAME}/tlsca-cert.pem \
    --mspdir $TEMP_DIR/enrollments/${org}/users/${RCAADMIN_USER}/msp
}

function enroll_bootstrap_ECert_CA_users() {
  
  local org_name=$1
  push_fn "Enrolling bootstrap ECert CA user of ${org_name}"

  enroll_bootstrap_ECert_CA_user ${org_name} $ORG0_NS

  pop_fn
}