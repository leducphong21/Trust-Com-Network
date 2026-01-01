# Trust Com Network - Architecture Documentation

## Tổng Quan (Overview)

Trust Com Network là một giải pháp triển khai và quản lý mạng Hyperledger Fabric trên Kubernetes. Dự án cung cấp một cách đơn giản để thiết lập, phát triển và vận hành mạng blockchain thông qua các lệnh được tối ưu hóa và quy trình triển khai một lệnh.

## Cấu Trúc Dự Án (Project Structure)

```
Trust-Com-Network/
├── README.md                           # Tài liệu hướng dẫn sử dụng chính
├── LICENSE                             # Giấy phép Apache 2.0
├── .gitignore                          # Cấu hình Git ignore
├── asset-transfer-basic/               # Ví dụ smart contract cơ bản
│   ├── chaincode-java/                 # Chaincode viết bằng Java
│   ├── chaincode-external/             # Chaincode external
│   └── README.md
├── config/                             # Các file cấu hình Fabric
│   ├── core.yaml                       # Cấu hình peer
│   ├── orderer.yaml                    # Cấu hình orderer
│   └── configtx.yaml                   # Cấu hình channel
└── trust-com-network/                  # Thư mục chính của mạng
    ├── network                         # Script chính điều khiển toàn bộ mạng
    ├── env.example.sh                  # File cấu hình môi trường mẫu
    ├── README.md                       # Hướng dẫn chi tiết
    ├── scripts/                        # Các script hỗ trợ
    │   ├── utils.sh                    # Tiện ích logging và helper functions
    │   ├── prereqs.sh                  # Kiểm tra điều kiện tiên quyết
    │   ├── kind.sh                     # Quản lý KIND cluster
    │   ├── cluster.sh                  # Quản lý Kubernetes cluster
    │   ├── fabric_config.sh            # Cấu hình Fabric
    │   ├── fabric_CAs.sh               # Quản lý Certificate Authorities
    │   ├── trust_com_network.sh        # Logic khởi động/tắt mạng
    │   ├── channel.sh                  # Quản lý channels
    │   ├── chaincode.sh                # Quản lý chaincode lifecycle
    │   ├── application_connection.sh   # Cấu hình kết nối cho applications
    │   ├── generate_kube_files.sh      # Sinh file Kubernetes YAML
    │   ├── generate_configtx.sh        # Sinh file configtx.yaml động
    │   ├── generate_ccp.sh             # Sinh connection profiles
    │   ├── organization.sh             # Quản lý tổ chức
    │   └── monitoring.sh               # Cài đặt monitoring
    └── templates/                      # Templates cho Kubernetes và configs
        ├── kube/                       # Kubernetes YAML templates
        │   └── aws/                    # Templates cho AWS deployment
        ├── config/                     # Configuration templates
        ├── grafana/                    # Grafana dashboards
        └── template_new_org.json       # Template thêm tổ chức mới
```

## Kiến Trúc Hệ Thống (System Architecture)

### 1. Các Thành Phần Chính (Main Components)

#### a. Network Script (`network`)
Script chính điều khiển toàn bộ vòng đời của mạng Fabric. Nó hoạt động như một command router, nhận lệnh từ người dùng và phân phối đến các module tương ứng.

**Chức năng chính:**
- Khởi tạo và cấu hình môi trường
- Phân tích command line arguments
- Điều phối các operations đến sub-scripts
- Quản lý logging và error handling

**Commands được hỗ trợ:**
- `kind` / `unkind`: Tạo/xóa KIND cluster
- `cluster`: Quản lý Kubernetes cluster
- `up` / `down`: Khởi động/tắt mạng Fabric
- `channel`: Quản lý channels
- `chaincode`: Quản lý chaincode lifecycle
- `org`: Quản lý organizations
- `monitoring`: Cài đặt monitoring stack

#### b. Certificate Authority System (fabric_CAs.sh)
Quản lý hệ thống Certificate Authorities cho mạng Fabric.

**Chức năng:**
- Khởi tạo TLS certificate issuers sử dụng cert-manager
- Launch ECert CAs cho mỗi organization
- Enroll bootstrap CA users (rcaadmin)
- Quản lý TLS và ECert certificates

**Workflow:**
1. Tạo self-signing root TLS certificate issuer
2. Tạo TLS cert issuers cho từng organization
3. Deploy Fabric CA containers
4. Enroll rcaadmin user để quản lý CA

#### c. Network Lifecycle (trust_com_network.sh)
Quản lý vòng đời của network nodes (peers và orderers).

**Các hàm chính:**
- `network_up()`: Khởi động toàn bộ mạng
  - Khởi tạo namespace và storage
  - Load org configs
  - Setup k8s builder roles
  - Khởi tạo CAs
  - Enroll users
  - Tạo local MSPs
  - Launch orderers và peers

- `network_down()`: Tắt mạng
  - Dừng tất cả services
  - Xóa persistent volumes
  - Clean up namespace

- `add_peer()`: Thêm peer mới vào organization
  - Generate peer YAML
  - Tạo local MSP
  - Launch peer

#### d. Channel Management (channel.sh)
Quản lý toàn bộ lifecycle của channels.

**Các operations:**
- `create-org-admin`: Tạo admin users cho organizations
- `create-channel-msp`: Tạo MSP configuration cho channel
- `create-genesis-block`: Tạo genesis block cho channel
- `up`: Join orderers và peers vào channel
- `join-orderer`: Join orderer vào channel
- `join-peer`: Join peer vào channel
- `fetch-config`: Lấy channel configuration
- `get-modify-config`: Lấy và chỉnh sửa config
- `create-config-update-envelope`: Tạo config update envelope
- `sign`: Ký config update
- `update-config`: Submit config update

**Channel Workflow:**
1. Register và enroll org admins
2. Tạo channel MSP với certificates của tất cả orgs
3. Generate configtx.yaml và tạo genesis block
4. Join orderers vào channel
5. Join peers vào channel
6. Set anchor peers

#### e. Chaincode Lifecycle (chaincode.sh)
Quản lý chaincode từ packaging đến deployment.

**Các operations:**
- `deploy`: Thực hiện toàn bộ quy trình deployment
- `package`: Tạo chaincode package
- `install`: Cài đặt chaincode trên peers
- `approve`: Approve chaincode definition cho org
- `commit`: Commit chaincode definition lên channel
- `invoke`: Gọi chaincode transaction
- `query`: Query chaincode state

**Deployment Workflow:**
1. Build chaincode Docker image
2. Package chaincode
3. Tính chaincode ID
4. Launch chaincode service (nếu dùng ccaas)
5. Install chaincode trên tất cả peers
6. Approve chaincode cho từng organization
7. Commit chaincode definition

#### f. Configuration Generators

**generate_configtx.sh:**
- Generate `configtx.yaml` động dựa trên env variables
- Hỗ trợ multiple organizations
- Cấu hình orderer endpoints và consenters
- Tạo endorsement policies

**generate_kube_files.sh:**
- Generate Kubernetes YAML files từ templates
- Substitute environment variables
- Tạo deployment files cho:
  - Certificate Authorities
  - Orderers
  - Peers
  - Storage volumes
  - Network policies

**generate_ccp.sh:**
- Generate Connection Profiles cho client applications
- Bao gồm peer endpoints, CA endpoints, certificates

### 2. Kubernetes Integration

#### Storage Architecture
- **Persistent Volumes**: Lưu trữ ledger data, certificates, MSPs
- **Volume Claims**: Mỗi peer/orderer có PVC riêng
- **Scrub Jobs**: Kubernetes Jobs để clean volumes khi cần

#### Service Mesh
- **Ingress Controller**: Nginx ingress cho external access
- **Services**: ClusterIP services cho internal communication
- **TLS**: cert-manager quản lý TLS certificates

#### Deployment Strategy
- **Rolling Updates**: Zero-downtime updates
- **Health Checks**: Liveness và readiness probes
- **Resource Limits**: CPU và memory limits cho containers

### 3. Security Architecture

#### Certificate Management
- **TLS Certificates**: cert-manager với self-signed root CA
- **ECert (Enrollment Certificates)**: Fabric CA quản lý identity
- **MSP (Membership Service Provider)**: Local và channel MSPs

#### Identity Hierarchy
```
Root CA (cert-manager)
├── TLS CA per Org
│   ├── Orderer TLS certs
│   └── Peer TLS certs
└── Fabric CA per Org
    ├── Admin identities
    ├── Peer identities
    └── User identities
```

#### Access Control
- **Kubernetes RBAC**: Service accounts cho k8s builder
- **Fabric Policies**: Endorsement, reader, writer, admin policies
- **Network Policies**: Kubernetes network segmentation

## Workflow Hoàn Chỉnh (Complete Workflow)

### 1. Khởi Tạo Môi Trường (Environment Setup)
```bash
cd trust-com-network
cp env.example.sh env.sh
# Chỉnh sửa env.sh với cấu hình của bạn
./network generate-kube
```

**Quá trình:**
1. Load environment variables từ `env.sh`
2. Generate `configtx.yaml` từ template
3. Generate Kubernetes YAML files cho tất cả components
4. Prepare configuration directories

### 2. Tạo Kubernetes Cluster
```bash
./network kind
./network cluster init
```

**Quá trình:**
1. Tạo KIND cluster với Docker
2. Setup local registry cho images
3. Deploy ingress-nginx controller
4. Install cert-manager
5. Configure networking

### 3. Khởi Động Mạng (Network Launch)
```bash
./network up
```

**Quá trình chi tiết:**
1. **Namespace Setup**: Tạo namespace cho network
2. **Storage Setup**: Tạo PVs và PVCs
3. **Load Configs**: Load configuration cho orderer và orgs
4. **K8s Builder**: Setup service accounts nếu dùng k8s builder
5. **TLS Setup**: 
   - Tạo root TLS issuer
   - Tạo TLS issuers cho từng org
6. **CA Deployment**:
   - Deploy Fabric CAs
   - Wait for CAs ready
7. **User Enrollment**:
   - Enroll rcaadmin users
8. **MSP Creation**:
   - Register và enroll orderers
   - Register và enroll peers
   - Tạo local MSP configs
9. **Node Launch**:
   - Launch orderers
   - Launch peers
   - Wait for all deployments ready

### 4. Tạo và Khởi Động Channel
```bash
./network channel create-org-admin
./network channel create-channel-msp
./network channel create-genesis-block
./network channel up
```

**Quá trình:**
1. **Create Org Admin**:
   - Register org admin identities
   - Enroll org admins
2. **Create Channel MSP**:
   - Copy certificates từ tất cả orgs
   - Tạo channel MSP structure
3. **Create Genesis Block**:
   - Generate configtx.yaml
   - Sử dụng configtxgen tạo genesis block
4. **Channel Up**:
   - Join tất cả orderers vào channel
   - Join tất cả peers vào channel
   - Set anchor peers

### 5. Deploy Chaincode
```bash
./network chaincode deploy asset-transfer-basic ../asset-transfer-basic/chaincode-java 1
./network chaincode commit asset-transfer-basic 1
```

**Quá trình:**
1. **Prepare**:
   - Build chaincode Docker image
   - Package chaincode
2. **Launch** (if ccaas):
   - Deploy chaincode service
3. **Install**:
   - Install trên tất cả peers
4. **Approve**:
   - Approve cho từng org
5. **Commit**:
   - Commit definition lên channel

### 6. Invoke và Query
```bash
./network chaincode invoke asset-transfer-basic '{"Args":["InitLedger"]}'
./network chaincode query asset-transfer-basic '{"Args":["ReadAsset","asset1"]}'
```

## Design Patterns và Best Practices

### 1. Modular Architecture
- Mỗi module (script) có trách nhiệm riêng biệt
- Loose coupling giữa các modules
- Interface rõ ràng thông qua exported functions

### 2. Configuration Management
- Environment variables cho runtime config
- Templates cho reusable configurations
- Dynamic generation thay vì static files

### 3. Error Handling
- Set errexit để dừng khi có lỗi
- Logging system với success/error indicators
- Debug logs riêng biệt

### 4. Idempotency
- Operations có thể chạy lại safely
- Check trạng thái trước khi thực hiện
- Cleanup jobs có thể rerun

### 5. Extensibility
- Easy để thêm organizations mới
- Support multiple peers per org
- Template-based configuration

## Monitoring và Operations

### Logging System
- **network.log**: High-level workflow và status
- **network-debug.log**: Detailed debug information
- Real-time tail của log file
- Visual indicators (✅, ⚠️, ☠️)

### Monitoring Stack
- **Prometheus**: Metrics collection
- **Grafana**: Visualization
- **Pre-configured dashboards**: Fabric-specific metrics

### Troubleshooting
- Check pod status: `kubectl get pods -n <namespace>`
- Check logs: `kubectl logs -n <namespace> <pod-name>`
- Check certificates: Verify in TEMP_DIR
- Check network: Test connectivity giữa components

## Điểm Mạnh (Strengths)

1. **One-Command Setup**: Đơn giản hóa deployment phức tạp
2. **Kubernetes-Native**: Tận dụng K8s orchestration
3. **Flexible**: Chạy trên nhiều K8s platforms (KIND, Rancher, EKS)
4. **Modular**: Dễ maintain và extend
5. **Production-Ready**: TLS, monitoring, proper MSP structure
6. **Cloud-Ready**: Template hỗ trợ AWS và cloud deployments

## Cải Tiến Có Thể (Potential Improvements)

1. **Input Validation**: Better argument parsing (Argbash)
2. **CA Stability**: Fix TCP connection rejection bug
3. **Flexible Paths**: Support relative paths
4. **Configuration**: User/pass auth for TLS và ecert
5. **Chaincode**: Support multiple chaincode runtimes
6. **Documentation**: Inline comments cho complex functions

## Kết Luận

Trust Com Network là một giải pháp mạnh mẽ và well-architected cho việc triển khai Hyperledger Fabric trên Kubernetes. Code được tổ chức tốt, modular, và follow best practices. Hệ thống logging, error handling, và configuration management đều được implement cẩn thận. Đây là một foundation tốt cho cả development và production deployments.
