#!/usr/bin/env bash

set -euo pipefail

function generate_kube_files() {
  echo "📁 Generating Kubernetes files..."

  mkdir -p kube

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
