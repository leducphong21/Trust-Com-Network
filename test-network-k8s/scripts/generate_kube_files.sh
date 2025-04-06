#!/usr/bin/env bash

set -euo pipefail

function generate_kube_files() {
  echo "📁 Generating Kubernetes files..."

  mkdir -p kube/org0

  echo "📦 Generating for orderer org: ${ORDERER_NAME}"

  ORG_DIR="kube/${ORDERER_NAME}"

  # Generate orderers for org0
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    sed \
      -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
      -e "s/{{ORDERER_NUM}}/${i}/g" \
      kube/templates/orderer/orderer-template.yaml \
      > "${ORG_DIR}/${ORDERER_NAME}-orderer${i}.yaml"
  done

  # Generate CA for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    kube/templates/orderer/ca-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-ca.yaml"

  # Generate TLS Issuer for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    kube/templates/orderer/tls-cert-issuer-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-tls-cert-issuer.yaml"

  # Generate Root TLS Issuer for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    kube/templates/orderer/root-tls-cert-issuer-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-root-tls-cert-issuer.yaml"

  # Generate Scrub Volumes Job for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    kube/templates/orderer/job-scrub-fabric-volumes-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-job-scrub-fabric-volumes.yaml"

  echo "✅ Done for ${ORDERER_NAME}"


  for ORG in ${ORG_NAMES}; do
    ORG_DIR="kube/${ORG}"
    mkdir -p "${ORG_DIR}"

    echo "📦 Generating for org: ${ORG}"

    ## Generate peers
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      sed \
        -e "s/{{ORG_NAME}}/${ORG}/g" \
        -e "s/{{PEER_NUM}}/${i}/g" \
        kube/templates/peer-template.yaml \
        > "${ORG_DIR}/${ORG}-peer${i}.yaml"
    done

    ## Generate CA
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      kube/templates/ca-template.yaml \
      > "${ORG_DIR}/${ORG}-ca.yaml"

    ## TLS Issuer
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      kube/templates/tls-cert-issuer-template.yaml \
      > "${ORG_DIR}/${ORG}-tls-cert-issuer.yaml"

    ## Install builder
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      kube/templates/install-k8s-builder-template.yaml \
      > "${ORG_DIR}/${ORG}-install-k8s-builder.yaml"

    ## Scrub Volumes Job
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      kube/templates/job-scrub-fabric-volumes-template.yaml \
      > "${ORG_DIR}/${ORG}-job-scrub-fabric-volumes.yaml"

    echo "✅ Done for ${ORG}"
  done

  echo "🏁 All kube files generated in ./kube/<org>/"
}
