#!/usr/bin/env bash

set -euo pipefail

function generate_kube_files() {
  echo "📁 Generating Kubernetes files..."

  cp templates/kube/*.yaml kube

  mkdir -p kube/${ORDERER_NAME}
  mkdir -p config/${ORDERER_NAME}

  echo "📦 Generating for orderer org: ${ORDERER_NAME}"

  ORG_DIR="kube/${ORDERER_NAME}"

  # Generate orderers for org0
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    sed \
      -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
      -e "s/{{ORDERER_NUM}}/${i}/g" \
      templates/kube/orderer/orderer-template.yaml \
      > "${ORG_DIR}/${ORDERER_NAME}-orderer${i}.yaml"
  done

  # Generate CA for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/kube/orderer/ca-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-ca.yaml"

  # Generate TLS Issuer for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/kube/orderer/tls-cert-issuer-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-tls-cert-issuer.yaml"

  # Generate Root TLS Issuer for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/kube/orderer/root-tls-cert-issuer-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-root-tls-cert-issuer.yaml"

  # Generate Scrub Volumes Job for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/kube/orderer/job-scrub-fabric-volumes-template.yaml \
    > "${ORG_DIR}/${ORDERER_NAME}-job-scrub-fabric-volumes.yaml"

  # Generate PVC for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/kube/orderer/pvc-fabric-template.yaml \
    > "kube/pvc-fabric-${ORDERER_NAME}.yaml"

  # Generate Config Map for org0
  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/config/orderer/fabric-ca-server-config-template.yaml \
    > "config/${ORDERER_NAME}/fabric-ca-server-config.yaml"

  sed \
    -e "s/{{ORDERER}}/${ORDERER_NAME}/g" \
    templates/config/orderer/core-template.yaml \
    > "config/${ORDERER_NAME}/core.yaml"

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
        templates/kube/org/peer-template.yaml \
        > "${ORG_DIR}/${ORG}-peer${i}.yaml"
    done

    ## Generate CA
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/kube/org/ca-template.yaml \
      > "${ORG_DIR}/${ORG}-ca.yaml"

    ## TLS Issuer
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/kube/org/tls-cert-issuer-template.yaml \
      > "${ORG_DIR}/${ORG}-tls-cert-issuer.yaml"

    ## Install builder
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/kube/org/install-k8s-builder-template.yaml \
      > "${ORG_DIR}/${ORG}-install-k8s-builder.yaml"

    ## Scrub Volumes Job
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/kube/org/job-scrub-fabric-volumes-template.yaml \
      > "${ORG_DIR}/${ORG}-job-scrub-fabric-volumes.yaml"

    ## Generate PVC
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/kube/org/pvc-fabric-template.yaml \
      > "kube/pvc-fabric-${ORG}.yaml"

    echo "✅ Done for ${ORG}"
    
    # Generate Config Map
    ORG_CONFIG_MAP_DIR="config/${ORG}"
    mkdir -p "$ORG_CONFIG_MAP_DIR"
    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/config/org/fabric-ca-server-config-template.yaml \
      > "config/${ORG}/fabric-ca-server-config.yaml"

    sed \
      -e "s/{{ORG_NAME}}/${ORG}/g" \
      templates/config/org/core-template.yaml \
      > "config/${ORG}/core.yaml"
    done

  echo "🏁 All kube files generated in ./kube/<org>/"
}
