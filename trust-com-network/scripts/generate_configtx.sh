#!/bin/bash

# scripts/generate_configtx.sh

function generate_configtx() {
  mkdir -p "${TEMP_DIR}/${CHANNEL_NAME}"
  local CONFIG_FILE="${TEMP_DIR}/${CHANNEL_NAME}/configtx.yaml"
  local TEMPLATE_FILE="${TEMP_DIR}/org_template.yaml"

  # Xóa file cũ nếu tồn tại
  rm -f "$CONFIG_FILE"

  # Tạo template cho tổ chức
  cat << 'EOF' > "$TEMPLATE_FILE"
  - &{{ORG_NAME}}
    # DefaultOrg defines the organization which is used in the sampleconfig
    # of the fabric.git development environment
    Name: {{ORG_NAME}}MSP

    # ID to load the MSP definition as
    ID: {{ORG_NAME}}MSP

    MSPDir: ./channel-msp/peerOrganizations/{{ORG_NAME}}/msp

    # Policies defines the set of policies at this level of the config tree
    # For organization policies, their canonical path is usually
    #   /Channel/<Application|Orderer>/<OrgName>/<PolicyName>
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

    # leave this flag set to true.
    AnchorPeers:
      # AnchorPeers defines the location of peers which can be used
      # for cross org gossip communication.  Note, this value is only
      # encoded in the genesis block in the Application section context
      - Host: {{ORG_NAME}}-peer1.${NS}.svc.cluster.local
        Port: 7051
EOF

  # Tạo danh sách OrdererEndpoints dựa trên NUM_ORDERERS
  ORDERER_ENDPOINTS=""
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    ORDERER_ENDPOINTS="${ORDERER_ENDPOINTS}      - ${ORDERER_NAME}-orderer${i}.${NS}.svc.cluster.local:6050
"
  done

  # Tạo danh sách Consenters dựa trên NUM_ORDERERS
  CONSENTERS=""
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    CONSENTERS="${CONSENTERS}      - Host: ${ORDERER_NAME}-orderer${i}
        Port: 6050
        ClientTLSCert: ./channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer${i}/tls/signcerts/tls-cert.pem
        ServerTLSCert: ./channel-msp/ordererOrganizations/${ORDERER_NAME}/orderers/${ORDERER_NAME}-orderer${i}/tls/signcerts/tls-cert.pem
"
  done

  # Tạo danh sách Endorsement Rule
  ENDORSEMENT_RULE="      Rule: \"OR("
  local i=0
  for ORG_NAME in ${ORGS_IN_CHANNEL}; do
    ENDORSEMENT_RULE="${ENDORSEMENT_RULE}'${ORG_NAME}MSP.peer'"
    if [ $i -lt $((NUM_ORGS-1)) ]; then
      ENDORSEMENT_RULE="${ENDORSEMENT_RULE}, "
    fi
    i=$((i+1))
  done
  ENDORSEMENT_RULE="${ENDORSEMENT_RULE})\""

  # Tạo danh sách Organizations trong Profiles
  ORG_LIST=""
  for ORG_NAME in ${ORGS_IN_CHANNEL}; do
    ORG_LIST="${ORG_LIST}        - *${ORG_NAME}
"
  done

  # Tạo danh sách tổ chức động từ template
  ORG_SECTIONS=$(for ORG_NAME in ${ORGS_IN_CHANNEL}; do
    cat "$TEMPLATE_FILE" | sed "s/{{CHANNEL_NAME}}/${CHANNEL_NAME}/g" | sed "s/{{ORG_NAME}}/${ORG_NAME}/g" | sed "s/\${NS}/${NS}/g"
  done)

  # Ghi toàn bộ nội dung YAML vào file
  cat << EOF > "$CONFIG_FILE"
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

---
################################################################################
#
#   Section: Organizations
#
#   - This section defines the different organizational identities which will
#   be referenced later in the configuration.
#
################################################################################
Organizations:

  # SampleOrg defines an MSP using the sampleconfig.  It should never be used
  # in production but may be used as a template for other definitions
  - &OrdererOrg
    # DefaultOrg defines the organization which is used in the sampleconfig
    # of the fabric.git development environment
    Name: OrdererOrg

    # ID to load the MSP definition as
    ID: ordererMSP

    # MSPDir is the filesystem path which contains the MSP configuration
    MSPDir: ./channel-msp/ordererOrganizations/${ORDERER_NAME}/msp

    # Policies defines the set of policies at this level of the config tree
    # For organization policies, their canonical path is usually
    #   /Channel/<Application|Orderer>/<OrgName>/<PolicyName>
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('ordererMSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('ordererMSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('ordererMSP.admin')"

    OrdererEndpoints:
${ORDERER_ENDPOINTS}
${ORG_SECTIONS}
################################################################################
#
#   SECTION: Capabilities
#
#   - This section defines the capabilities of fabric network. This is a new
#   concept as of v1.1.0 and should not be utilized in mixed networks with
#   v1.0.x peers and orderers.  Capabilities define features which must be
#   present in a fabric binary for that binary to safely participate in the
#   fabric network.  For instance, if a new MSP type is added, newer binaries
#   might recognize and validate the signatures from this type, while older
#   binaries without this support would be unable to validate those
#   transactions.  This could lead to different versions of the fabric binaries
#   having different world states.  Instead, defining a capability for a channel
#   informs those binaries without this capability that they must cease
#   processing transactions until they have been upgraded.  For v1.0.x if any
#   capabilities are defined (including a map with all capabilities turned off)
#   then the v1.0.x peer will deliberately crash.
#
################################################################################
Capabilities:
  # Channel capabilities apply to both the orderers and the peers and must be
  # supported by both.
  # Set the value of the capability to true to require it.
  Channel: &ChannelCapabilities
    # V2_0 capability ensures that orderers and peers behave according
    # to v2.0 channel capabilities. Orderers and peers from
    # prior releases would behave in an incompatible way, and are therefore
    # not able to participate in channels at v2.0 capability.
    # Prior to enabling V2.0 channel capabilities, ensure that all
    # orderers and peers on a channel are at v2.0.0 or later.
    V2_0: true

  # Orderer capabilities apply only to the orderers, and may be safely
  # used with prior release peers.
  # Set the value of the capability to true to require it.
  Orderer: &OrdererCapabilities
    # V2_0 orderer capability ensures that orderers behave according
    # to v2.0 orderer capabilities. Orderers from
    # prior releases would behave in an incompatible way, and are therefore
    # not able to participate in channels at v2.0 orderer capability.
    # Prior to enabling V2.0 orderer capabilities, ensure that all
    # orderers on channel are at v2.0.0 or later.
    V2_0: true

  # Application capabilities apply only to the peer network, and may be safely
  # used with prior release peers.
  # Set the value of the capability to true to require it.
  Application: &ApplicationCapabilities
    # V2_0 application capability ensures that peers behave according
    # to v2.0 application capabilities. Peers from
    # prior releases would behave in an incompatible way, and are therefore
    # not able to participate in channels at v2.0 application capability.
    # Prior to enabling V2.0 application capabilities, ensure that all
    # peers on channel are at v2.0.0 or later.
    V2_5: true

################################################################################
#
#   SECTION: Application
#
#   - This section defines the values to encode into a config transaction or
#   genesis block for application related parameters
#
################################################################################
Application: &ApplicationDefaults

  # Organizations is the list of orgs which are defined as participants on
  # the application side of the network
  Organizations:

  # Policies defines the set of policies at this level of the config tree
  # For Application policies, their canonical path is
  #   /Channel/Application/<PolicyName>
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

################################################################################
#
#   SECTION: Orderer
#
#   - This section defines the values to encode into a config transaction or
#   genesis block for orderer related parameters
#
################################################################################
Orderer: &OrdererDefaults

  # Orderer Type: The orderer implementation to start
  OrdererType: etcdraft

  EtcdRaft:
    Consenters:
${CONSENTERS}
    # Options to be specified for all the etcd/raft nodes. The values here
    # are the defaults for all new channels and can be modified on a
    # per-channel basis via configuration updates.
    Options:
      # TickInterval is the time interval between two Node.Tick invocations.
      #TickInterval: 500ms default
      TickInterval: 2500ms

      # ElectionTick is the number of Node.Tick invocations that must pass
      # between elections. That is, if a follower does not receive any
      # message from the leader of current term before ElectionTick has
      # elapsed, it will become candidate and start an election.
      # ElectionTick must be greater than HeartbeatTick.
      # ElectionTick: 10 default
      ElectionTick: 5

      # HeartbeatTick is the number of Node.Tick invocations that must
      # pass between heartbeats. That is, a leader sends heartbeat
      # messages to maintain its leadership every HeartbeatTick ticks.
      HeartbeatTick: 1

      # MaxInflightBlocks limits the max number of in-flight append messages
      # during optimistic replication phase.
      MaxInflightBlocks: 5

      # SnapshotIntervalSize defines number of bytes per which a snapshot is taken
      SnapshotIntervalSize: 16 MB

  # Batch Timeout: The amount of time to wait before creating a batch
  BatchTimeout: 2s

  # Batch Size: Controls the number of messages batched into a block
  BatchSize:

    # Max Message Count: The maximum number of messages to permit in a batch
    MaxMessageCount: 10

    # Absolute Max Bytes: The absolute maximum number of bytes allowed for
    # the serialized messages in a batch.
    AbsoluteMaxBytes: 99 MB

    # Preferred Max Bytes: The preferred maximum number of bytes allowed for
    # the serialized messages in a batch. A message larger than the preferred
    # max bytes will result in a batch larger than preferred max bytes.
    PreferredMaxBytes: 512 KB

  # Organizations is the list of orgs which are defined as participants on
  # the orderer side of the network
  Organizations:

  # Policies defines the set of policies at this level of the config tree
  # For Orderer policies, their canonical path is
  #   /Channel/Orderer/<PolicyName>
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
    # BlockValidation specifies what signatures must be included in the block
    # from the orderer for the peer to validate it.
    BlockValidation:
      Type: ImplicitMeta
      Rule: "ANY Writers"

################################################################################
#
#   CHANNEL
#
#   This section defines the values to encode into a config transaction or
#   genesis block for channel related parameters.
#
################################################################################
Channel: &ChannelDefaults
  # Policies defines the set of policies at this level of the config tree
  # For Channel policies, their canonical path is
  #   /Channel/<PolicyName>
  Policies:
    # Who may invoke the 'Deliver' API
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    # Who may invoke the 'Broadcast' API
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    # By default, who may modify elements at this config level
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"

  # Capabilities describes the channel level capabilities, see the
  # dedicated Capabilities section elsewhere in this file for a full
  # description
  Capabilities:
    <<: *ChannelCapabilities

################################################################################
#
#   Profile
#
#   - Different configuration profiles may be encoded here to be specified
#   as parameters to the configtxgen tool
#
################################################################################
Profiles:

  # test network profile with application (not system) channel.
  TwoOrgsApplicationGenesis:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      Organizations:
        - *OrdererOrg
      Capabilities: *OrdererCapabilities
    Application:
      <<: *ApplicationDefaults
      Organizations:
${ORG_LIST}
      Capabilities: *ApplicationCapabilities
EOF

  # Xóa file template tạm thời
  rm -f "$TEMPLATE_FILE"

  log "Generated configtx.yaml with ${NUM_ORGS} organizations: ${ORG_NAMES}"
}

# Hàm log giả định (nếu chưa có)
log() {
  echo "$1"
}