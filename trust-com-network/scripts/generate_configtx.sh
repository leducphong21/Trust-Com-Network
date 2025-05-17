#!/bin/bash

# scripts/generate_configtx.sh

function generate_configtx() {
  if [ -z "$TEMP_DIR" ] || [ -z "$ORDERER_NAMES_CHANNEL" ] || [ -z "$ORDERER_ORG_COUNTS" ] || [ -z "$ORG_NAMES_CHANNEL" ] || [ -z "$NS" ] || [ -z "$NUM_ORGS" ]; then
    log "Error: Required environment variables (TEMP_DIR, ORDERER_NAMES_CHANNEL, ORDERER_ORG_COUNTS, ORG_NAMES, NS, NUM_ORGS) are not set."
    exit 1
  fi

  mkdir -p "${TEMP_DIR}"
  local CONFIG_FILE="${TEMP_DIR}/configtx.yaml"
  local ORG_TEMPLATE_FILE="${TEMP_DIR}/org_template.yaml"
  local ORDERER_TEMPLATE_FILE="${TEMP_DIR}/orderer_template.yaml"

  rm -f "$CONFIG_FILE"

  cat << 'EOF' > "$ORG_TEMPLATE_FILE"
  - &{{ORG_NAME}}
    Name: {{ORG_NAME}}MSP
    ID: {{ORG_NAME}}MSP
    MSPDir: ./channel-msp/peerOrganizations/{{ORG_NAME}}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('{{ORG_NAME}}MSP.admin', '{{ORG_NAME}}MSP.peer', '{{ORG_NAME}}MSP.client')"
      Writers:
        Type: Signature
        Rule: "OR('{{ORG_NAME}}MSP.admin', '{{ORG_NAME}}MSP.client')"
      Admins:
        Type: Signature
        Rule: "OR('{{ORG_NAME}}MSP.admin')"
      Endorsement:
        Type: Signature
        Rule: "OR('{{ORG_NAME}}MSP.peer')"
    AnchorPeers:
      - Host: {{ORG_NAME}}-peer1.{{NS}}.svc.cluster.local
        Port: 7051
EOF

  cat << 'EOF' > "$ORDERER_TEMPLATE_FILE"
  - &{{ORDERER_NAME}}
    Name: {{ORDERER_NAME}}MSP
    ID: {{ORDERER_NAME}}MSP
    MSPDir: ./channel-msp/ordererOrganizations/{{ORDERER_NAME}}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('{{ORDERER_NAME}}MSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('{{ORDERER_NAME}}MSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('{{ORDERER_NAME}}MSP.admin')"
    OrdererEndpoints:
{{ORDERER_ENDPOINTS}}
EOF

  ORDERER_SECTIONS=""
  CONSENTERS=""
  declare -a CONSENTERS_ARRAY

  read -ra ORDERER_NAME_ARRAY <<< "$ORDERER_NAMES_CHANNEL"
  read -ra ORDERER_COUNT_ARRAY <<< "$ORDERER_ORG_COUNTS"

  for index in "${!ORDERER_NAME_ARRAY[@]}"; do
    ORDERER_NAME="${ORDERER_NAME_ARRAY[$index]}"
    NUM_ORDERERS="${ORDERER_COUNT_ARRAY[$index]}"

    declare -a ORG_ENDPOINTS_ARRAY=()
    for ((i=1; i<=NUM_ORDERERS; i++)); do
      ORG_ENDPOINTS_ARRAY+=("      - ${ORDERER_NAME}-orderer${i}.${NS}.svc.cluster.local:6050")
      CONSENTERS_ARRAY+=("      - Host: ${ORDERER_NAME}-orderer${i}")
      CONSENTERS_ARRAY+=("        Port: 6050")
      CONSENTERS_ARRAY+=("        ClientTLSCert: ./channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer${i}/tls/signcerts/tls-cert.pem")
      CONSENTERS_ARRAY+=("        ServerTLSCert: ./channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer${i}/tls/signcerts/tls-cert.pem")
    done

    ORG_ENDPOINTS=$(printf "%s\n" "${ORG_ENDPOINTS_ARRAY[@]}")
    TEMP_ORDERER_FILE="${TEMP_DIR}/temp_orderer_${ORDERER_NAME}.yaml"
    cat "$ORDERER_TEMPLATE_FILE" | sed "s/{{ORDERER_NAME}}/${ORDERER_NAME}/g" > "$TEMP_ORDERER_FILE"
    echo -e "${ORG_ENDPOINTS}" > "${TEMP_DIR}/endpoints.txt"
    sed -i "/{{ORDERER_ENDPOINTS}}/r ${TEMP_DIR}/endpoints.txt" "$TEMP_ORDERER_FILE"
    sed -i "/{{ORDERER_ENDPOINTS}}/d" "$TEMP_ORDERER_FILE"
    ORDERER_SECTIONS="${ORDERER_SECTIONS}$(cat "$TEMP_ORDERER_FILE")\n"
    rm -f "${TEMP_DIR}/endpoints.txt" "$TEMP_ORDERER_FILE"
  done

  CONSENTERS=$(printf "%s\n" "${CONSENTERS_ARRAY[@]}")

  ENDORSEMENT_RULE="      Rule: \"OR("
  local i=0
  for ORG_NAME in ${ORG_NAMES}; do
    ENDORSEMENT_RULE="${ENDORSEMENT_RULE}'${ORG_NAME}MSP.peer'"
    if [ $i -lt $((NUM_ORGS-1)) ]; then
      ENDORSEMENT_RULE="${ENDORSEMENT_RULE}, "
    fi
    i=$((i+1))
  done
  ENDORSEMENT_RULE="${ENDORSEMENT_RULE})\""

  declare -a ORG_LIST_ARRAY
  for ORG_NAME in ${ORG_NAMES}; do
    ORG_LIST_ARRAY+=("        - *${ORG_NAME}")
  done
  ORG_LIST=$(printf "%s\n" "${ORG_LIST_ARRAY[@]}")

  declare -a ORDERER_ORG_LIST_ARRAY
  for ORDERER_NAME in ${ORDERER_NAMES_CHANNEL}; do
    ORDERER_ORG_LIST_ARRAY+=("        - *${ORDERER_NAME}")
  done
  ORDERER_ORG_LIST=$(printf "%s\n" "${ORDERER_ORG_LIST_ARRAY[@]}")

  ORG_SECTIONS=""
  for ORG_NAME in ${ORG_NAMES}; do
    ORG_SECTIONS="${ORG_SECTIONS}$(cat "$ORG_TEMPLATE_FILE" | sed "s/{{ORG_NAME}}/${ORG_NAME}/g" | sed "s/{{NS}}/${NS}/g")\n"
  done

  cat << EOF > "$CONFIG_FILE"
---
Organizations:
$(echo -e "${ORDERER_SECTIONS}${ORG_SECTIONS}")

Capabilities:
  Channel: &ChannelCapabilities
    V2_0: true
  Orderer: &OrdererCapabilities
    V2_0: true
  Application: &ApplicationCapabilities
    V2_5: true

Application: &ApplicationDefaults
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    LifecycleEndorsement:
      Type: Signature
${ENDORSEMENT_RULE}
    Endorsement:
      Type: Signature
${ENDORSEMENT_RULE}
  Capabilities:
    <<: *ApplicationCapabilities

Orderer: &OrdererDefaults
  OrdererType: etcdraft
  EtcdRaft:
    Consenters:
$(echo -e "${CONSENTERS}")
    Options:
      TickInterval: 2500ms
      ElectionTick: 5
      HeartbeatTick: 1
      MaxInflightBlocks: 5
      SnapshotIntervalSize: 16 MB
  BatchTimeout: 2s
  BatchSize:
    MaxMessageCount: 10
    AbsoluteMaxBytes: 99 MB
    PreferredMaxBytes: 512 KB
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    BlockValidation:
      Type: ImplicitMeta
      Rule: "ANY Writers"

Channel: &ChannelDefaults
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
  Capabilities:
    <<: *ChannelCapabilities

Profiles:
  TwoOrgsApplicationGenesis:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      Organizations:
$(echo -e "${ORDERER_ORG_LIST}")
      Capabilities: *OrdererCapabilities
    Application:
      <<: *ApplicationDefaults
      Organizations:
$(echo -e "${ORG_LIST}")
      Capabilities: *ApplicationCapabilities
EOF

  rm -f "$ORG_TEMPLATE_FILE" "$ORDERER_TEMPLATE_FILE"

  log "Generated configtx.yaml with ${NUM_ORGS} peer orgs and orderer orgs: ${ORDERER_NAMES_CHANNEL}"
}

log() {
  echo "$1"
}