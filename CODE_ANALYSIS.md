# Trust Com Network - Code Analysis & Documentation

## Phân Tích Chi Tiết Source Code (Detailed Source Code Analysis)

Tài liệu này cung cấp phân tích chi tiết về implementation của từng component trong Trust Com Network.

## Table of Contents

1. [Main Network Script](#main-network-script)
2. [Utilities and Helper Functions](#utilities-and-helper-functions)
3. [Certificate Authority Management](#certificate-authority-management)
4. [Network Lifecycle Management](#network-lifecycle-management)
5. [Channel Management](#channel-management)
6. [Chaincode Management](#chaincode-management)
7. [Configuration Generation](#configuration-generation)
8. [Kubernetes Integration](#kubernetes-integration)
9. [Security Implementation](#security-implementation)
10. [Design Patterns Used](#design-patterns-used)

---

## Main Network Script

### File: `trust-com-network/network`

#### Purpose
Entry point và command router cho toàn bộ Trust Com Network operations.

#### Key Design Elements

##### 1. Context Management Pattern
```bash
function context() {
  local name=$1
  local default_value=$2
  local override_name=TEST_NETWORK_${name}
  
  export ${name}="${!override_name:-${default_value}}"
}
```

**Explanation:**
- Cho phép override environment variables với prefix `TEST_NETWORK_`
- Sử dụng indirect variable expansion `${!override_name}`
- Fallback to default value nếu không có override
- Export để sub-shells có thể access

**Example:**
```bash
# Default behavior
context FABRIC_VERSION 2.5
# FABRIC_VERSION=2.5

# Override
export TEST_NETWORK_FABRIC_VERSION=3.0
context FABRIC_VERSION 2.5
# FABRIC_VERSION=3.0
```

##### 2. Module Loading
```bash
. scripts/utils.sh
. scripts/prereqs.sh
. scripts/kind.sh
# ... more scripts
```

**Why this approach:**
- Sourcing (`.`) loads functions into current shell
- Functions available immediately
- Shared environment và variables
- No need for complex import mechanisms

##### 3. Command Routing Pattern
```bash
MODE=$1
shift

if [ "${MODE}" == "kind" ]; then
  kind_init
elif [ "${MODE}" == "up" ]; then
  network_up
elif [ "${MODE}" == "channel" ]; then
  channel_command_group $@
# ... more modes
fi
```

**Design Benefits:**
- Simple if-elif chain for clarity
- Early shift removes MODE from arguments
- Pass remaining args with $@
- Command groups for hierarchical commands

---

## Utilities and Helper Functions

### File: `scripts/utils.sh`

#### 1. Logging System Implementation

##### Initialization
```bash
function logging_init() {
  printf '' > ${LOG_FILE} > ${DEBUG_FILE}  # Reset logs
  tail -f ${LOG_FILE} &                    # Stream to STDOUT
  trap "exit_fn" EXIT                      # Cleanup on exit
  exec 1>>${DEBUG_FILE} 2>>${DEBUG_FILE}   # Redirect to debug
  sleep 0.5                                 # Avoid race condition
}
```

**Key Points:**
- **Dual logging**: Control flow (LOG_FILE) và debug info (DEBUG_FILE)
- **Background tail**: Real-time output while capturing details
- **File descriptor redirection**: All child output to debug log
- **Trap handler**: Cleanup khi script exits
- **Race condition fix**: Sleep ensures tail starts before logging

##### Operation Logging
```bash
function push_fn() {
  echo -ne "   - $@ ..." >> ${LOG_FILE}
}

function pop_fn() {
  if [ $# -eq 0 ]; then
    echo -ne "\r✅" >> ${LOG_FILE}
    return
  fi
  
  local res=$1
  if [ $res -eq 0 ]; then
    echo -ne "\r✅\n" >> ${LOG_FILE}
  elif [ $res -eq 1 ]; then
    echo -ne "\r⚠️\n" >> ${LOG_FILE}
  else
    echo -ne "\r☠️\n" >> ${LOG_FILE}
  fi
  
  if [ $res -ne 0 ]; then
    tail -${LOG_ERROR_LINES} network-debug.log >> ${LOG_FILE}
  fi
}
```

**Visual Feedback:**
- ✅ Success (exit code 0)
- ⚠️ Warning (exit code 1)
- ☠️ Fatal error (other exit codes)
- Automatic error details from debug log

**Usage Pattern:**
```bash
function my_operation() {
  push_fn "Description of operation"
  
  # Do work
  kubectl apply -f file.yaml
  
  pop_fn  # Automatically shows ✅
}
```

#### 2. Template Application
```bash
function apply_template() {
  echo "Applying template $1:"
  cat $1 | envsubst                        # Preview
  cat $1 | envsubst | kubectl -n $2 apply -f -  # Apply
}
```

**Process:**
1. Read template file
2. Substitute environment variables với envsubst
3. Pipe to kubectl apply
4. Preview output for debugging

**envsubst variables:**
```yaml
# Template
name: ${ORG_NAME}-peer${PEER_NUM}

# After envsubst (với ORG_NAME=bank, PEER_NUM=1)
name: bank-peer1
```

#### 3. Peer Context Management
```bash
function export_peer_context() {
  local org=$1
  local peer=$2
  
  export FABRIC_CFG_PATH=${PWD}/config/${org}
  export CORE_PEER_ADDRESS=${org}-${peer}.${DOMAIN}:${NGINX_HTTPS_PORT}
  export CORE_PEER_MSPCONFIGPATH=${TEMP_DIR}/enrollments/${org}/users/${org}admin/msp
  export CORE_PEER_TLS_ROOTCERT_FILE=${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/peerOrganizations/${org}/msp/tlscacerts/tlsca-signcert.pem
}
```

**Purpose:**
- Set environment variables để peer CLI commands target correct peer
- Cần thiết cho chaincode operations
- Each invocation changes global peer context

**Usage:**
```bash
export_peer_context bank peer1
peer chaincode query ...  # Queries bank-peer1
```

---

## Certificate Authority Management

### File: `scripts/fabric_CAs.sh`

#### 1. TLS Certificate Issuers

```bash
function init_tls_cert_issuers_org() {
  local org_name=$1
  
  # Create root self-signing issuer
  kubectl -n $NS apply -f kube/root-tls-cert-issuer.yaml
  kubectl -n $NS wait --timeout=30s --for=condition=Ready issuer/root-tls-cert-issuer
  
  # Create org-specific issuer
  kubectl -n $NS apply -f kube/${org_name}/${org_name}-tls-cert-issuer.yaml
  kubectl -n $NS wait --timeout=30s --for=condition=Ready issuer/${org_name}-tls-cert-issuer
}
```

**Certificate Hierarchy:**
```
root-tls-cert-issuer (self-signed)
├── bank-tls-cert-issuer
│   ├── bank-ca TLS cert
│   ├── bank-peer1 TLS cert
│   └── bank-peer2 TLS cert
└── land-tls-cert-issuer
    ├── land-ca TLS cert
    ├── land-peer1 TLS cert
    └── land-peer2 TLS cert
```

**Why cert-manager:**
- Automatic certificate generation
- Renewal handling
- Kubernetes-native
- No manual certificate management

#### 2. Fabric CA Deployment

```bash
function launch_ECert_CAs_org() {
  local org_name=$1
  
  apply_template kube/${org_name}/${org_name}-ca.yaml $NS
  kubectl -n $NS rollout status deploy/${org_name}-ca
  
  sleep 5  # Workaround cho connection bug
}
```

**CA Container:**
- Runs Fabric CA server
- Uses TLS cert từ cert-manager
- Persistent volume cho CA database
- Bootstrap với rcaadmin user

#### 3. Bootstrap User Enrollment

```bash
function enroll_bootstrap_ECert_CA_user() {
  local org=$1
  local ns=$2
  
  CA_NAME=${org}-ca
  CA_DIR=${TEMP_DIR}/cas/${CA_NAME}
  
  # Get CA's TLS cert từ Kubernetes secret
  kubectl -n $ns get secret ${CA_NAME}-tls-cert -o json \
    | jq -r .data.\"ca.crt\" \
    | base64 -d \
    > ${CA_DIR}/tlsca-cert.pem
  
  # Enroll rcaadmin
  fabric-ca-client enroll \
    --url https://${RCAADMIN_USER}:${RCAADMIN_PASS}@${CA_NAME}.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls.certfiles ${CA_DIR}/tlsca-cert.pem \
    --mspdir $TEMP_DIR/enrollments/${org}/users/${RCAADMIN_USER}/msp
}
```

**Process Flow:**
1. CA deploys với bootstrap admin (rcaadmin/rcaadminpw)
2. Extract TLS cert từ K8s secret (created by cert-manager)
3. Enroll rcaadmin từ outside cluster
4. Use rcaadmin credentials để register other identities

**Security Note:**
- Bootstrap credentials hardcoded (should be configurable)
- TLS required for all CA communication
- Admin MSP stored locally for subsequent registrations

---

## Network Lifecycle Management

### File: `scripts/trust_com_network.sh`

#### 1. Node MSP Creation

```bash
function create_node_local_MSP() {
  local node_type=$1    # peer or orderer
  local org=$2          # Organization
  local node=$3         # Node name
  local csr_hosts=$4    # Certificate SAN
  local ns=$5           # Namespace
  
  local id_name=${org}-${node}
  local id_secret=${node_type}pw
  local ca_name=${org}-ca
  
  # Register identity với CA
  fabric-ca-client register \
    --id.name ${id_name} \
    --id.secret ${id_secret} \
    --id.type ${node_type} \
    --url https://${ca_name}.${DOMAIN}:${NGINX_HTTPS_PORT} \
    --tls.certfiles $TEMP_DIR/cas/${ca_name}/tlsca-cert.pem \
    --mspdir $TEMP_DIR/enrollments/${org}/users/${RCAADMIN_USER}/msp
  
  # Enroll inside container to write to persistent volume
  cat <<EOF | kubectl -n ${ns} exec deploy/${ca_name} -i -- /bin/sh
    fabric-ca-client enroll \
      --url https://${id_name}:${id_secret}@${ca_name} \
      --csr.hosts ${csr_hosts} \
      --mspdir /var/hyperledger/fabric/organizations/${node_type}Organizations/${org}.example.com/${node_type}s/${id_name}.${org}.example.com/msp
    
    # Create MSP config
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
```

**Two-Step Process:**

**Step 1: Register (outside cluster)**
- Use rcaadmin credentials
- Registers identity với CA
- CA stores identity in database

**Step 2: Enroll (inside cluster)**
- Exec into CA container
- Enroll generates certificates
- Writes directly to persistent volume
- Volume mounted by peer/orderer container
- Creates NodeOUs config for identity classification

**NodeOUs Configuration:**
- Enables OU-based identity classification
- peer OU: Identifies peer identities
- client OU: Identifies client identities
- admin OU: Identifies admin identities
- orderer OU: Identifies orderer identities

**Why kubectl exec:**
- Certificates created directly in shared volume
- No need to copy certificates into cluster
- Available immediately when container starts
- Simpler than volume mounting from outside

#### 2. Network Startup Orchestration

```bash
function network_up() {
  # Phase 1: Infrastructure
  init_namespace
  init_storage_volumes
  load_org_config (for all orgs)
  
  # Phase 2: Security (if k8s builder)
  apply_k8s_builder_roles
  apply_k8s_builders
  
  # Phase 3: Certificate Authorities
  init_tls_cert_issuers_org (for all orgs)
  launch_ECert_CAs_org (for all orgs)
  enroll_bootstrap_ECert_CA_users (for all orgs)
  
  # Phase 4: Identity Creation
  create_local_MSP_orderer (for all orderers)
  create_local_MSP (for all peers in all orgs)
  
  # Phase 5: Node Launch
  launch_orderers (all orderers)
  launch_peers (all peers in all orgs)
}
```

**Critical Ordering:**
1. Infrastructure first (namespace, storage)
2. Security setup if needed
3. CAs must be running before enrollment
4. Bootstrap users must be enrolled before node registration
5. Node MSPs must exist before launching nodes
6. Orderers before peers (standard practice)

**Parallel vs Sequential:**
- CAs can launch in parallel (per org)
- MSP creation must be sequential (CA load)
- Node launches can be parallel within constraints

#### 3. Network Teardown

```bash
function network_down() {
  # Safety check
  kubectl get namespace $ns > /dev/null || return
  
  # Stop all services
  stop_services
  
  # Clean persistent data
  scrub_org_volumes
  
  # Remove namespace
  delete_namespace
  
  # Clean local files
  rm -rf $TEMP_DIR
  rm -rf $PWD/kube
  rm -rf $PWD/config
}
```

**Cleanup Order:**
1. Stop running pods (graceful shutdown)
2. Clean persistent volumes (scrub job)
3. Delete namespace (cascades to all resources)
4. Remove local temporary files

**Scrub Volumes Implementation:**
```bash
function scrub_org_volumes() {
  for org in ${ORG_NAMES}; do
    kubectl -n ${NS} delete jobs --all
    kubectl -n ${NS} create -f kube/${org}/${org}-job-scrub-fabric-volumes.yaml
    kubectl -n ${NS} wait --for=condition=complete --timeout=60s job/job-scrub-fabric-volumes
    kubectl -n ${NS} delete jobs --all
  done
}
```

**Why scrub job:**
- Persistent volumes retain data
- Simple kubectl delete doesn't clean PV content
- Job mounts volume và runs `rm -rf *`
- Ensures clean state for next network_up

---

## Channel Management

### File: `scripts/channel.sh`

#### 1. Channel Creation Workflow

##### Step 1: Create Org Admins
```bash
function create_org_admin() {
  register_org_admins
  enroll_org_admins
}
```

**Process:**
- Register admin identity for each org
- Enroll to get certificates
- Admins có authority để manage channel

##### Step 2: Create Channel MSP
```bash
function create_channel_MSP() {
  # Copy certificates từ all orgs to channel MSP directory
  for org in ${ORG_NAMES}; do
    mkdir -p ${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/peerOrganizations/${org}/msp/
    cp -r ${source_msp}/* ${dest_msp}/
  done
  
  # Similar for orderers
}
```

**Channel MSP Structure:**
```
channel-msp/
├── peerOrganizations/
│   ├── bank/
│   │   └── msp/
│   │       ├── cacerts/
│   │       ├── tlscacerts/
│   │       └── config.yaml
│   └── land/
│       └── msp/
└── ordererOrganizations/
    └── orderer/
        └── msp/
```

**Purpose:**
- Centralized trust root cho channel
- All orgs' CA certificates
- Used by configtxgen để create genesis block
- Defines who can participate in channel

##### Step 3: Create Genesis Block
```bash
function create_genesis_block() {
  # Generate configtx.yaml
  generate_configtx
  
  # Use configtxgen to create genesis block
  configtxgen \
    -profile TwoOrgsApplicationGenesis \
    -channelID ${CHANNEL_NAME} \
    -outputBlock ${TEMP_DIR}/${CHANNEL_NAME}/${CHANNEL_NAME}_genesis_block.pb \
    -configPath ${TEMP_DIR}/${CHANNEL_NAME}
}
```

**configtxgen:**
- Fabric tool to generate channel artifacts
- Reads configtx.yaml
- Produces genesis block (protobuf format)
- Genesis block defines initial channel configuration

##### Step 4: Join Nodes to Channel
```bash
function channel_up() {
  # Join orderers
  for orderer in ${ORDERERS}; do
    join_channel_orderer ${orderer}
  done
  
  # Join peers
  for org in ${ORG_NAMES}; do
    for peer in ${PEERS}; do
      join_channel_peer ${org} ${peer}
    done
  done
}
```

**Join Process:**

**For Orderers:**
```bash
osnadmin channel join \
  --channelID ${CHANNEL_NAME} \
  --config-block ${genesis_block}
```

**For Peers:**
```bash
peer channel join \
  -b ${genesis_block}
```

#### 2. Channel Configuration Updates

##### Fetch Current Config
```bash
function fetch_channel_config() {
  export_peer_context ${ORG} peer1
  
  # Fetch config block
  peer channel fetch config config_block.pb \
    -c ${CHANNEL_NAME} \
    -o ${ORDERER_ADDRESS}
  
  # Decode to JSON
  configtxlator proto_decode \
    --input config_block.pb \
    --type common.Block \
    | jq .data.data[0].payload.data.config > config.json
}
```

**configtxlator:**
- Translates protobuf ↔ JSON
- Allows human-readable config editing
- Essential for config updates

##### Modify Config
```bash
function get-modify-config() {
  fetch_channel_config
  
  # User modifies config.json manually
  cp config.json modified_config.json
  
  # Edit modified_config.json as needed
}
```

##### Create Update Envelope
```bash
function create-config-update-envelope() {
  # Encode original
  configtxlator proto_encode \
    --input config.json \
    --type common.Config \
    --output config.pb
  
  # Encode modified
  configtxlator proto_encode \
    --input modified_config.json \
    --type common.Config \
    --output modified_config.pb
  
  # Compute delta
  configtxlator compute_update \
    --channel_id ${CHANNEL_NAME} \
    --original config.pb \
    --updated modified_config.pb \
    --output config_update.pb
  
  # Wrap in envelope
  configtxlator proto_decode \
    --input config_update.pb \
    --type common.ConfigUpdate \
    | jq . > config_update.json
  
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'${CHANNEL_NAME}'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' > config_update_in_envelope.json
  
  configtxlator proto_encode \
    --input config_update_in_envelope.json \
    --type common.Envelope \
    --output config_update_in_envelope.pb
}
```

**Config Update Process:**
1. Original config → protobuf
2. Modified config → protobuf
3. Compute delta (only changes)
4. Wrap delta in envelope
5. Sign envelope (next step)
6. Submit to orderer

##### Sign Update
```bash
function sign() {
  local org=$1
  
  export_peer_context ${org} peer1
  
  peer channel signconfigtx \
    -f config_update_in_envelope.pb
}
```

**Signature Requirements:**
- Based on channel policy
- Typically requires majority of orgs
- Each org signs separately
- Signatures accumulated in envelope

##### Submit Update
```bash
function update-config() {
  local org=$1
  
  export_peer_context ${org} peer1
  
  peer channel update \
    -f config_update_in_envelope.pb \
    -c ${CHANNEL_NAME} \
    -o ${ORDERER_ADDRESS}
}
```

---

## Chaincode Management

### File: `scripts/chaincode.sh`

#### 1. Chaincode Lifecycle (Fabric 2.x+)

**Fabric 2.x introduced new lifecycle:**
1. Package
2. Install
3. Approve (per org)
4. Commit (channel-wide)

#### 2. Package Chaincode

```bash
function package_chaincode() {
  local cc_name=$1
  local cc_label=$2
  local cc_package=$3
  
  if [ "${CHAINCODE_BUILDER}" == "ccaas" ]; then
    # Chaincode as a Service package
    cat > connection.json <<EOF
{
  "address": "${cc_name}:9999",
  "dial_timeout": "10s",
  "tls_required": false
}
EOF
    
    cat > metadata.json <<EOF
{
  "type": "ccaas",
  "label": "${cc_label}"
}
EOF
    
    tar -czf code.tar.gz connection.json
    tar -czf ${cc_package} metadata.json code.tar.gz
  fi
}
```

**CCAASPackage Structure:**
```
chaincode.tgz
├── metadata.json      # Chaincode label và type
└── code.tar.gz        # Connection info
    └── connection.json  # Where to connect
```

**Why CCAAS:**
- Chaincode runs as separate service
- Not embedded in peer container
- Easier development và debugging
- Kubernetes-native deployment

#### 3. Chaincode ID Calculation

```bash
function set_chaincode_id() {
  local package_file=$1
  
  CHAINCODE_ID=$(peer lifecycle chaincode calculatepackageid ${package_file})
  export CHAINCODE_ID
}
```

**Package ID:**
- Hash of package content
- Unique identifier for this specific package
- Used to reference installed chaincode
- Format: `label:hash`

#### 4. Launch Chaincode Service

```bash
function launch_chaincode() {
  local cc_name=$1
  local cc_id=$2
  local cc_image=$3
  
  # Create deployment YAML
  cat > chaincode-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${cc_name}
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: chaincode
        image: ${cc_image}
        env:
        - name: CHAINCODE_SERVER_ADDRESS
          value: "0.0.0.0:9999"
        - name: CHAINCODE_ID
          value: "${cc_id}"
EOF
  
  kubectl apply -f chaincode-deployment.yaml -n ${NS}
}
```

**Service Architecture:**
```
Peer Container                 Chaincode Container
├── Peer Process              ├── Chaincode Server (port 9999)
└── Connects to chaincode     └── Implements chaincode logic
         ↓
    Service Discovery
         ↓
    ${cc_name}:9999
```

#### 5. Install Chaincode

```bash
function install_chaincode_for_org() {
  local cc_name=$1
  local cc_package=$2
  local org=$3
  local peer=$4
  
  export_peer_context ${org} ${peer}
  
  peer lifecycle chaincode install ${cc_package}
}
```

**Install Process:**
- Package copied to peer's filesystem
- Peer extracts package
- Makes chaincode available for approval
- Each peer must install independently

**Query Installed:**
```bash
peer lifecycle chaincode queryinstalled
```

Output shows package ID needed for approval.

#### 6. Approve Chaincode

```bash
function approve_chaincode_for_org() {
  local cc_name=$1
  local sequence=$2
  local org=$3
  
  export_peer_context ${org} peer1
  
  peer lifecycle chaincode approveformyorg \
    -o ${ORDERER_ADDRESS} \
    --channelID ${CHANNEL_NAME} \
    --name ${cc_name} \
    --version 1.0 \
    --package-id ${CHAINCODE_ID} \
    --sequence ${sequence} \
    --tls \
    --cafile ${ORDERER_TLS_CERT}
}
```

**Approval:**
- Organization endorses chaincode definition
- Specifies package ID to use
- Each org must approve independently
- Policy determines how many approvals needed

**Check Commit Readiness:**
```bash
peer lifecycle chaincode checkcommitreadiness \
  --channelID ${CHANNEL_NAME} \
  --name ${cc_name} \
  --version 1.0 \
  --sequence ${sequence}
```

Shows which orgs have approved.

#### 7. Commit Chaincode

```bash
function commit_chaincode_for_channel() {
  local cc_name=$1
  local sequence=$2
  
  export_peer_context ${FIRST_ORG} peer1
  
  # Build peer addresses for all orgs
  PEER_ADDRESSES=""
  for org in ${ORG_NAMES}; do
    PEER_ADDRESSES="$PEER_ADDRESSES --peerAddresses ${org}-peer1.${DOMAIN}:${PORT}"
  done
  
  peer lifecycle chaincode commit \
    -o ${ORDERER_ADDRESS} \
    --channelID ${CHANNEL_NAME} \
    --name ${cc_name} \
    --version 1.0 \
    --sequence ${sequence} \
    ${PEER_ADDRESSES} \
    --tls \
    --cafile ${ORDERER_TLS_CERT}
}
```

**Commit:**
- Makes chaincode definition active on channel
- All peers learn about chaincode
- Ready for invocations
- Only needs to be done once (not per org)

**Query Committed:**
```bash
peer lifecycle chaincode querycommitted \
  --channelID ${CHANNEL_NAME}
```

#### 8. Invoke and Query

```bash
function invoke_chaincode() {
  local cc_name=$1
  local args=$2
  
  export_peer_context ${FIRST_ORG} peer1
  
  peer chaincode invoke \
    -o ${ORDERER_ADDRESS} \
    --channelID ${CHANNEL_NAME} \
    --name ${cc_name} \
    -c "${args}" \
    --tls \
    --cafile ${ORDERER_TLS_CERT}
}

function query_chaincode() {
  local cc_name=$1
  local args=$2
  
  export_peer_context ${FIRST_ORG} peer1
  
  peer chaincode query \
    --channelID ${CHANNEL_NAME} \
    --name ${cc_name} \
    -c "${args}"
}
```

**Invoke vs Query:**
- **Invoke**: Modifies ledger, requires consensus
- **Query**: Reads ledger, local to peer

---

## Configuration Generation

### File: `scripts/generate_configtx.sh`

#### Dynamic configtx.yaml Generation

```bash
function generate_configtx() {
  mkdir -p "${TEMP_DIR}/${CHANNEL_NAME}"
  local CONFIG_FILE="${TEMP_DIR}/${CHANNEL_NAME}/configtx.yaml"
  
  # Create org template
  cat << 'EOF' > org_template.yaml
  - &{{ORG_NAME}}
    Name: {{ORG_NAME}}MSP
    ID: {{ORG_NAME}}MSP
    MSPDir: ./channel-msp/peerOrganizations/{{ORG_NAME}}/msp
    Policies: ...
    AnchorPeers:
      - Host: {{ORG_NAME}}-peer1.${NS}.svc.cluster.local
        Port: 7051
EOF
  
  # Generate org sections
  ORG_SECTIONS=$(for ORG_NAME in ${ORGS_IN_CHANNEL}; do
    cat org_template.yaml | sed "s/{{ORG_NAME}}/${ORG_NAME}/g"
  done)
  
  # Generate orderer endpoints
  ORDERER_ENDPOINTS=""
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    ORDERER_ENDPOINTS="${ORDERER_ENDPOINTS}      - ${ORDERER_NAME}-orderer${i}.${NS}.svc.cluster.local:6050\n"
  done
  
  # Write complete configtx.yaml
  cat << EOF > "$CONFIG_FILE"
Organizations:
${ORG_SECTIONS}

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
    ...

Orderer: &OrdererDefaults
  OrdererType: ${ORDERER_TYPE}
  Addresses:
${ORDERER_ENDPOINTS}
  ...

Channel: &ChannelDefaults
  Policies:
    ...

Profiles:
  TwoOrgsApplicationGenesis:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      Organizations:
        - *${ORDERER_NAME}
    Application:
      <<: *ApplicationDefaults
      Organizations:
${ORG_LIST}
EOF
}
```

**Why Dynamic Generation:**
- Supports variable number of orgs
- No manual config file editing
- Consistent with env.sh settings
- Easy to add/remove organizations

**Template Variables:**
- `{{ORG_NAME}}`: Replaced with each org name
- `${NS}`: Kubernetes namespace
- `${NUM_ORDERERS}`: Number of orderers
- `${ORDERER_TYPE}`: raft or bft

**YAML Anchors:**
- `&ApplicationDefaults`: Define defaults
- `*ApplicationDefaults`: Reference defaults
- `<<: *ApplicationDefaults`: Merge defaults

---

## Kubernetes Integration

### Template System

#### Example: Peer Deployment Template

```yaml
# templates/kube/org/peer-template.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${ORG_NAME}-peer${PEER_NUM}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${ORG_NAME}-peer${PEER_NUM}
  template:
    metadata:
      labels:
        app: ${ORG_NAME}-peer${PEER_NUM}
        org: ${ORG_NAME}
    spec:
      containers:
      - name: peer
        image: ${FABRIC_PEER_IMAGE}
        env:
        - name: CORE_PEER_ID
          value: ${ORG_NAME}-peer${PEER_NUM}
        - name: CORE_PEER_ADDRESS
          value: ${ORG_NAME}-peer${PEER_NUM}:7051
        - name: CORE_PEER_GOSSIP_EXTERNALENDPOINT
          value: ${ORG_NAME}-peer${PEER_NUM}.${DOMAIN}:${NGINX_HTTPS_PORT}
        volumeMounts:
        - name: fabric-volume
          mountPath: /var/hyperledger
        - name: fabric-config
          mountPath: /etc/hyperledger/fabric
      volumes:
      - name: fabric-volume
        persistentVolumeClaim:
          claimName: fabric-${ORG_NAME}
```

**Key Points:**
- All ${VAR} replaced by envsubst
- Labels for service discovery
- Persistent volume for data
- Environment variables configure peer

### Storage Management

```yaml
# Persistent Volume Claim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fabric-${ORG_NAME}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
```

**Storage Strategy:**
- One PVC per organization
- Shared by all containers in org
- Contains: MSPs, certificates, ledger data
- ReadWriteMany for multi-pod access

### Ingress Configuration

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fabric-ingress
spec:
  rules:
  - host: ${ORG_NAME}-peer1.${DOMAIN}
    http:
      paths:
      - path: /
        backend:
          service:
            name: ${ORG_NAME}-peer1
            port:
              number: 7051
```

**Ingress Benefits:**
- External access to peers
- TLS termination
- Load balancing
- Domain-based routing

---

## Security Implementation

### TLS Architecture

```
cert-manager (Certificate Management)
└── root-tls-cert-issuer (Self-signed root)
    ├── bank-tls-cert-issuer
    │   ├── bank-ca-tls-cert
    │   ├── bank-peer1-tls-cert
    │   └── bank-peer2-tls-cert
    └── land-tls-cert-issuer
        ├── land-ca-tls-cert
        ├── land-peer1-tls-cert
        └── land-peer2-tls-cert
```

### Identity Management

**Three Identity Types:**

1. **TLS Identities** (cert-manager)
   - Secure network communication
   - Server authentication
   - Client authentication

2. **ECert Identities** (Fabric CA)
   - Transaction signing
   - Identity verification
   - MSP membership

3. **Admin Identities** (Fabric CA)
   - Channel management
   - Chaincode deployment
   - Configuration updates

### Policies

**Channel Policies:**
```yaml
Readers:
  Type: Signature
  Rule: "OR('Org1MSP.member', 'Org2MSP.member')"

Writers:
  Type: Signature
  Rule: "OR('Org1MSP.member', 'Org2MSP.member')"

Admins:
  Type: Signature
  Rule: "OR('Org1MSP.admin', 'Org2MSP.admin')"

Endorsement:
  Type: Signature
  Rule: "AND('Org1MSP.peer', 'Org2MSP.peer')"
```

**Policy Types:**
- **Signature**: Based on MSP identities
- **ImplicitMeta**: Aggregates other policies
- **Rule**: Boolean logic of MSP principals

---

## Design Patterns Used

### 1. Command Pattern
- Main `network` script as command dispatcher
- Sub-commands in separate modules
- Clean separation of concerns

### 2. Template Method Pattern
- `network_up()` defines algorithm skeleton
- Delegates steps to specialized functions
- Extensible for new organizations

### 3. Factory Pattern
- Dynamic generation of Kubernetes resources
- Templates + variables = configured resources
- Same template produces multiple instances

### 4. Observer Pattern
- Logging system observes operations
- Real-time feedback via tail
- Separation of logging from business logic

### 5. Strategy Pattern
- Different chaincode builders (ccaas, k8s)
- Different cluster runtimes (kind, k3s)
- Behavior selected via configuration

---

## Kết Luận

Trust Com Network source code demonstrates:

✅ **Solid Architecture**: Clear separation, modularity, extensibility

✅ **Production Ready**: Security, monitoring, error handling

✅ **Kubernetes Native**: Proper use of K8s primitives

✅ **Developer Friendly**: Logging, documentation, templates

✅ **Fabric Best Practices**: Proper CA usage, MSP structure, channel management

✅ **Maintainable**: Clear code structure, consistent patterns

Code quality cao, well-thought-out design, và comprehensive implementation. Đây là một excellent foundation cho Hyperledger Fabric deployments trên Kubernetes.
