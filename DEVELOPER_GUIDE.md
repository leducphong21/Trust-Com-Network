# Trust Com Network - Developer Guide

## Hướng Dẫn Cho Developers

Tài liệu này dành cho developers muốn hiểu sâu về codebase và contribute vào dự án Trust Com Network.

## Mục Lục

1. [Environment Setup](#environment-setup)
2. [Code Organization](#code-organization)
3. [Development Workflow](#development-workflow)
4. [Key Functions Explained](#key-functions-explained)
5. [Adding New Features](#adding-new-features)
6. [Testing](#testing)
7. [Debugging](#debugging)
8. [Contributing Guidelines](#contributing-guidelines)

## Environment Setup

### Prerequisites
```bash
# Cài đặt các tool cần thiết
brew install kubectl jq gettext kind docker

# Verify installations
kubectl version --client
jq --version
envsubst --version
kind version
docker --version
```

### Local Development Setup
```bash
# Clone repository
git clone https://github.com/leducphong21/Trust-Com-Network.git
cd Trust-Com-Network/trust-com-network

# Copy và configure environment
cp env.example.sh env.sh
vim env.sh  # Chỉnh sửa theo nhu cầu

# Generate Kubernetes files
./network generate-kube
```

### Understanding env.sh

File `env.sh` chứa tất cả configuration cho network:

```bash
ENV_NETWOK_NAME=bank              # Tên mạng Fabric
ENV_CLUSTER_NAME=bank-cluster     # Tên K8s cluster
ENV_DOMAIN=localho.st             # Domain cho ingress
ENV_NS=bank                       # Kubernetes namespace
ENV_CHANNEL_NAME=mychannel        # Tên channel
ENV_ORG_NAMES="bank land"         # Danh sách organizations (space-separated)
ENV_NUM_PEERS_PER_ORG=2           # Số peers mỗi org
ENV_ORDERER_NAME=orderer          # Tên orderer organization
ENV_NUM_ORDERERS=3                # Số orderers
ENV_ORGS_IN_CHANNEL="bank land"   # Orgs tham gia channel
ENV_ORDERER_TARGET=orderer-orderer1.localho.st  # Orderer endpoint
```

## Code Organization

### Main Entry Point: `network` Script

File `network` là entry point chính, structured như sau:

```bash
#!/usr/bin/env bash
set -o errexit          # Exit on error
. env.sh                # Load environment

# Context variables với override capability
context FABRIC_VERSION 2.5
context CLUSTER_RUNTIME kind
# ... more contexts

# Import all modules
. scripts/utils.sh
. scripts/prereqs.sh
. scripts/kind.sh
# ... more imports

# Command routing
if [ "${MODE}" == "up" ]; then
  network_up
elif [ "${MODE}" == "down" ]; then
  network_down
# ... more commands
fi
```

### Module Structure

Mỗi script trong `scripts/` directory có cấu trúc:

1. **Shebang và License**
```bash
#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
```

2. **Function Definitions**
- Prefix `push_fn` để log operation start
- Business logic
- Suffix `pop_fn` để log completion/error

3. **Command Group Functions** (nếu có sub-commands)
```bash
function xxx_command_group() {
  COMMAND=$1
  shift
  if [ "${COMMAND}" == "..." ]; then
    # handle command
  fi
}
```

## Development Workflow

### 1. Understanding the Logging System

File `scripts/utils.sh` implement logging system:

```bash
# Initialize logging
logging_init()
  - Reset log files
  - Tail network.log to STDOUT
  - Redirect child process output to debug log
  - Setup exit handler

# Log operations
push_fn "Operation description"
  - Write operation start to log

pop_fn [exit_code]
  - Write success (✅) or error (⚠️, ☠️)
  - Include error details if failed

# Simple logging
log "Message"
  - Write message to log file
```

**Best Practice:**
```bash
function my_operation() {
  push_fn "Doing something important"
  
  # Your logic here
  kubectl apply -f myfile.yaml
  kubectl wait --for=condition=ready ...
  
  pop_fn
}
```

### 2. Working with Templates

Templates sử dụng `envsubst` để substitute variables:

```yaml
# Template file: templates/kube/org/peer-template.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${ORG_NAME}-peer${PEER_NUM}
spec:
  template:
    spec:
      containers:
      - name: peer
        image: ${FABRIC_PEER_IMAGE}
        env:
        - name: CORE_PEER_ID
          value: ${ORG_NAME}-peer${PEER_NUM}
```

**Usage in code:**
```bash
# Set variables
export ORG_NAME="bank"
export PEER_NUM="1"
export FABRIC_PEER_IMAGE="hyperledger/fabric-peer:2.5"

# Generate file
cat templates/kube/org/peer-template.yaml | envsubst > kube/bank/bank-peer1.yaml

# Or use helper function
apply_template templates/kube/org/peer-template.yaml $NS
```

### 3. Certificate Management

Certificate workflow sử dụng Fabric CA:

```bash
# 1. Register identity
fabric-ca-client register \
  --id.name       ${id_name} \
  --id.secret     ${id_secret} \
  --id.type       peer \
  --url           https://${ca_name}.${DOMAIN}:${PORT} \
  --tls.certfiles ${tls_cert} \
  --mspdir        ${admin_msp}

# 2. Enroll identity (creates certificates)
fabric-ca-client enroll \
  --url https://${id_name}:${id_secret}@${ca_name} \
  --csr.hosts ${csr_hosts} \
  --mspdir ${output_msp}

# 3. Create MSP config.yaml
cat > ${msp_dir}/config.yaml <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${org}-ca.pem
    OrganizationalUnitIdentifier: client
  # ... more OUs
EOF
```

## Key Functions Explained

### network_up() - Master Orchestration

Location: `scripts/trust_com_network.sh`

```bash
function network_up() {
  # 1. Kubernetes setup
  init_namespace           # Create namespace
  init_storage_volumes     # Create PVCs
  
  # 2. Load configurations for all orgs
  load_org_config "$ORDERER_NAME"
  for ORG in ${ORG_NAMES}; do
    load_org_config ${ORG}
  done
  
  # 3. K8s builder (if using k8s chaincode builder)
  if [ "${CHAINCODE_BUILDER}" == "k8s" ]; then
    apply_k8s_builder_roles
    apply_k8s_builders
  fi
  
  # 4. Certificate issuers (TLS)
  init_tls_cert_issuers_org ${ORDERER_NAME}
  for ORG in ${ORG_NAMES}; do
    init_tls_cert_issuers_org ${ORG}
  done
  
  # 5. Launch CAs
  launch_ECert_CAs_org ${ORDERER_NAME}
  for ORG in ${ORG_NAMES}; do
    launch_ECert_CAs_org ${ORG}
  done
  
  # 6. Enroll bootstrap users
  enroll_bootstrap_ECert_CA_users ${ORDERER_NAME}
  for ORG in ${ORG_NAMES}; do
    enroll_bootstrap_ECert_CA_users ${ORG}
  done
  
  # 7. Create local MSPs for all nodes
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    create_local_MSP_orderer ${i}
  done
  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      create_local_MSP ${ORG} ${i}
    done
  done
  
  # 8. Launch all nodes
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    launch_orderers ${i}
  done
  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      launch_peers ${ORG} ${i}
    done
  done
}
```

**Key Points:**
- Sequential execution đảm bảo dependencies
- Loop through all orgs để ensure consistency
- Each step wait for completion trước khi next step

### create_node_local_MSP() - Identity Creation

Location: `scripts/trust_com_network.sh`

```bash
function create_node_local_MSP() {
  local node_type=$1    # "peer" or "orderer"
  local org=$2          # Organization name
  local node=$3         # Node name (e.g., "peer1")
  local csr_hosts=$4    # CSR hosts for certificate
  local ns=$5           # Kubernetes namespace
  
  local id_name=${org}-${node}
  local id_secret=${node_type}pw
  local ca_name=${org}-ca
  
  # Step 1: Register với CA (từ outside cluster)
  fabric-ca-client register \
    --id.name ${id_name} \
    --id.secret ${id_secret} \
    --id.type ${node_type} \
    --url https://${ca_name}.${DOMAIN}:${PORT} \
    --tls.certfiles $TEMP_DIR/cas/${ca_name}/tlsca-cert.pem \
    --mspdir $TEMP_DIR/enrollments/${org}/users/${RCAADMIN_USER}/msp
  
  # Step 2: Enroll từ inside cluster (kubectl exec)
  cat <<EOF | kubectl -n ${ns} exec deploy/${ca_name} -i -- /bin/sh
    fabric-ca-client enroll \
      --url https://${id_name}:${id_secret}@${ca_name} \
      --csr.hosts ${csr_hosts} \
      --mspdir /var/hyperledger/fabric/organizations/...
    
    # Create MSP config.yaml
    echo "NodeOUs:..." > .../msp/config.yaml
EOF
}
```

**Why exec into container?**
- Certificates được tạo trực tiếp trong persistent volume
- Available cho container khi start
- Không cần copy certificates vào cluster

### channel_up() - Channel Initialization

Location: `scripts/channel.sh`

```bash
function channel_up() {
  # Join orderers first
  for ((i=1; i<=NUM_ORDERERS; i++)); do
    join_channel_orderer "${ORDERER_NAME}" "orderer${i}"
  done
  
  # Wait for orderers to form consensus
  sleep 5
  
  # Join peers
  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      join_channel_peer ${ORG} peer${i}
    done
  done
  
  # Set anchor peers for each org
  for ORG in ${ORG_NAMES}; do
    set_anchor_peer ${ORG} peer1
  done
}
```

### deploy_chaincode() - Complete Chaincode Deployment

Location: `scripts/chaincode.sh`

```bash
function deploy_chaincode() {
  local cc_name=$1
  local cc_folder=$2
  local sequence=$3
  
  # 1. Build chaincode image
  prepare_chaincode_image ${cc_folder} ${cc_name}
  
  # 2. Package chaincode
  package_chaincode ${cc_name} ${cc_name} ${cc_package}
  
  # 3. Launch chaincode service (for ccaas)
  if [ "${CHAINCODE_BUILDER}" == "ccaas" ]; then
    set_chaincode_id ${cc_package}
    launch_chaincode ${cc_name} ${CHAINCODE_ID} ${CHAINCODE_IMAGE}
  fi
  
  # 4. Activate (install + approve + commit)
  activate_chaincode ${cc_name} ${cc_package} ${sequence}
}

function activate_chaincode() {
  local cc_name=$1
  local cc_package=$2
  local sequence=$3
  
  # Install on all peers
  for ORG in ${ORG_NAMES}; do
    for ((i=1; i<=NUM_PEERS_PER_ORG; i++)); do
      install_chaincode_for_org ${cc_name} ${cc_package} ${ORG} peer${i}
    done
  done
  
  # Approve for each org
  for ORG in ${ORG_NAMES}; do
    approve_chaincode_for_org ${cc_name} ${sequence} ${ORG}
  done
  
  # Commit (only once)
  commit_chaincode_for_channel ${cc_name} ${sequence}
}
```

## Adding New Features

### Example: Adding a New Command

1. **Add command handler in `network` script:**

```bash
elif [ "${MODE}" == "my-feature" ]; then
  log "Running my feature:"
  my_feature_function $@
  log "🏁 - My feature complete."
```

2. **Implement function in appropriate script:**

```bash
# scripts/my_module.sh
function my_feature_function() {
  local param1=$1
  local param2=$2
  
  push_fn "Doing my feature with ${param1}"
  
  # Your logic here
  # Use kubectl, fabric-ca-client, peer commands, etc.
  
  pop_fn
}
```

3. **Import script in `network`:**

```bash
. scripts/my_module.sh
```

### Example: Adding Support for New Organization

1. **Update env.sh:**
```bash
ENV_ORG_NAMES="bank land neworg"
ENV_ORGS_IN_CHANNEL="bank land neworg"
```

2. **Generate configs:**
```bash
./network generate-kube
```

3. **Templates automatically handle new org:**
- `generate_configtx.sh` loops through orgs
- `generate_kube_files.sh` creates files for each org
- `network_up()` processes all orgs

4. **Restart network:**
```bash
./network down
./network up
```

## Testing

### Manual Testing Workflow

```bash
# 1. Start fresh
./network down
./network unkind
./network kind

# 2. Initialize cluster
./network cluster init

# 3. Start network
./network up

# 4. Verify pods running
kubectl get pods -n ${NS}

# 5. Create channel
./network channel create-org-admin
./network channel create-channel-msp
./network channel create-genesis-block
./network channel up

# 6. Deploy and test chaincode
./network chaincode deploy asset-transfer-basic ../asset-transfer-basic/chaincode-java 1
./network chaincode commit asset-transfer-basic 1
./network chaincode invoke asset-transfer-basic '{"Args":["InitLedger"]}'
./network chaincode query asset-transfer-basic '{"Args":["ReadAsset","asset1"]}'

# 7. Cleanup
./network down
./network unkind
```

### Verification Checklist

- [ ] All pods running: `kubectl get pods -n ${NS}`
- [ ] CAs responding: `curl -k https://${org}-ca.${DOMAIN}:${PORT}/cainfo`
- [ ] Peers joined channel: `./network chaincode query <name> '{"Args":["..."]}'`
- [ ] Orderers consensus: Check orderer logs
- [ ] Chaincode installed: `peer lifecycle chaincode queryinstalled`
- [ ] Chaincode committed: `peer lifecycle chaincode querycommitted -C ${CHANNEL_NAME}`

## Debugging

### Common Issues and Solutions

#### 1. CA Connection Refused
```bash
# Symptom: TCP connection refused to CA after network down/up
# Workaround: 
sleep 10  # Already implemented in launch_ECert_CAs_org

# Debug:
kubectl logs -n ${NS} ${org}-ca-<pod-id>
kubectl describe pod -n ${NS} ${org}-ca-<pod-id>
```

#### 2. Certificate Issues
```bash
# Check certificates in temp directory
ls -la ${TEMP_DIR}/enrollments/${org}/users/
ls -la ${TEMP_DIR}/${CHANNEL_NAME}/channel-msp/

# Verify certificate content
openssl x509 -in certificate.pem -text -noout

# Check inside container
kubectl exec -n ${NS} deploy/${org}-peer1 -- ls -la /var/hyperledger/fabric/organizations/
```

#### 3. Channel Join Failures
```bash
# Check orderer logs
kubectl logs -n ${NS} ${ORDERER_NAME}-orderer1-<pod-id>

# Check peer logs
kubectl logs -n ${NS} ${org}-peer1-<pod-id>

# Verify genesis block
ls -la ${TEMP_DIR}/${CHANNEL_NAME}/${CHANNEL_NAME}_genesis_block.pb

# Try manual join
export_peer_context ${org} peer1
peer channel join -b ${TEMP_DIR}/${CHANNEL_NAME}/${CHANNEL_NAME}_genesis_block.pb
```

#### 4. Chaincode Issues
```bash
# Check chaincode pod logs (if using k8s builder)
kubectl logs -n ${NS} ${cc_name}-<pod-id>

# Check peer logs for chaincode
kubectl logs -n ${NS} ${org}-peer1-<pod-id> | grep ${cc_name}

# Verify package
peer lifecycle chaincode queryinstalled

# Verify approval
peer lifecycle chaincode checkcommitreadiness \
  --channelID ${CHANNEL_NAME} \
  --name ${cc_name} \
  --version 1.0 \
  --sequence ${sequence}
```

### Debug Logging

Enable debug logging:
```bash
# Check network-debug.log for detailed output
tail -f network-debug.log

# Enable verbose output in commands
set -x  # In script
# or
bash -x ./network up
```

### Kubernetes Debugging

```bash
# Get all resources
kubectl get all -n ${NS}

# Describe problematic resource
kubectl describe pod -n ${NS} <pod-name>
kubectl describe deploy -n ${NS} <deployment-name>

# Check events
kubectl get events -n ${NS} --sort-by='.lastTimestamp'

# Check persistent volumes
kubectl get pv
kubectl get pvc -n ${NS}

# Exec into container
kubectl exec -it -n ${NS} <pod-name> -- /bin/bash
```

## Contributing Guidelines

### Code Style

1. **Shell Script Style:**
   - Use bash features (arrays, etc.)
   - Always use `set -o errexit`
   - Use meaningful variable names
   - Comment complex logic

2. **Function Naming:**
   - Use snake_case
   - Descriptive names
   - Prefix helper functions with `_` if internal

3. **Error Handling:**
   - Use push_fn/pop_fn for operations
   - Check command exit codes
   - Provide meaningful error messages

### Pull Request Process

1. Fork repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Make changes with clear commits
4. Test thoroughly
5. Update documentation
6. Submit PR with description

### Documentation

- Update README.md for user-facing changes
- Update ARCHITECTURE.md for architectural changes
- Update this DEVELOPER_GUIDE.md for dev-facing changes
- Add inline comments for complex code

## Additional Resources

- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Fabric CA Documentation](https://hyperledger-fabric-ca.readthedocs.io/)
- [KIND Documentation](https://kind.sigs.k8s.io/)

## Contact

For questions or issues, please open an issue on GitHub or contact the maintainers.
