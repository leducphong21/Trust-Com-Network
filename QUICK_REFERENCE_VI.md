# Trust Com Network - Hướng Dẫn Nhanh (Quick Reference)

## Giới Thiệu

Tài liệu này là hướng dẫn nhanh bằng tiếng Việt để sử dụng Trust Com Network. Để hiểu sâu hơn về kiến trúc và cách hoạt động, vui lòng đọc:
- [ARCHITECTURE.md](ARCHITECTURE.md) - Kiến trúc tổng quan
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) - Hướng dẫn cho developers
- [CODE_ANALYSIS.md](CODE_ANALYSIS.md) - Phân tích chi tiết source code

## Mục Lục

1. [Cài Đặt Môi Trường](#cài-đặt-môi-trường)
2. [Khởi Động Nhanh](#khởi-động-nhanh)
3. [Các Lệnh Thường Dùng](#các-lệnh-thường-dùng)
4. [Quản Lý Channel](#quản-lý-channel)
5. [Quản Lý Chaincode](#quản-lý-chaincode)
6. [Quản Lý Tổ Chức](#quản-lý-tổ-chức)
7. [Troubleshooting](#troubleshooting)

---

## Cài Đặt Môi Trường

### Yêu Cầu Hệ Thống

```bash
# macOS
brew install kubectl jq gettext kind docker

# Linux (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y kubectl jq gettext-base
# Cài đặt kind và docker theo hướng dẫn riêng

# Kiểm tra cài đặt
kubectl version --client
jq --version
envsubst --version
kind version
docker --version
```

### Cấu Hình Môi Trường

```bash
cd trust-com-network

# Copy file cấu hình mẫu
cp env.example.sh env.sh

# Chỉnh sửa cấu hình
vim env.sh
```

**Các thông số quan trọng trong env.sh:**

```bash
# Tên mạng và cluster
ENV_NETWOK_NAME=bank              # Đặt tên cho mạng blockchain
ENV_CLUSTER_NAME=bank-cluster     # Tên Kubernetes cluster

# Domain và namespace
ENV_DOMAIN=localho.st             # Domain cho ingress (local: localho.st)
ENV_NS=bank                       # Kubernetes namespace

# Cấu hình channel
ENV_CHANNEL_NAME=mychannel        # Tên channel

# Cấu hình organizations
ENV_ORG_NAMES="bank land"                # Danh sách orgs (cách nhau bởi space)
ENV_NUM_PEERS_PER_ORG=2                  # Số peers mỗi org
ENV_ORGS_IN_CHANNEL="bank land"          # Orgs tham gia channel

# Cấu hình orderer
ENV_ORDERER_NAME=orderer                 # Tên orderer org
ENV_NUM_ORDERERS=3                       # Số orderers (ít nhất 3 cho production)
ENV_ORDERER_TARGET=orderer-orderer1.localho.st  # Orderer endpoint
```

---

## Khởi Động Nhanh

### Bước 1: Generate Kubernetes Files

```bash
cd trust-com-network
./network generate-kube
```

**Lệnh này sẽ:**
- Tạo file configtx.yaml
- Tạo các file Kubernetes YAML cho tất cả components
- Chuẩn bị các thư mục cấu hình

### Bước 2: Tạo Kubernetes Cluster (KIND)

```bash
# Tạo cluster
./network kind

# Khởi tạo cluster infrastructure
./network cluster init
```

**Lệnh cluster init sẽ:**
- Deploy ingress-nginx controller
- Cài đặt cert-manager
- Tạo local container registry
- Configure networking

### Bước 3: Khởi Động Mạng Fabric

```bash
./network up
```

**Quá trình khởi động (3-5 phút):**
1. ✅ Creating namespace
2. ✅ Creating storage volumes
3. ✅ Launching Certificate Authorities
4. ✅ Enrolling bootstrap users
5. ✅ Creating MSPs for all nodes
6. ✅ Launching orderers
7. ✅ Launching peers

### Bước 4: Tạo và Khởi Động Channel

```bash
# Tạo org admins
./network channel create-org-admin

# Tạo channel MSP
./network channel create-channel-msp

# Tạo genesis block
./network channel create-genesis-block

# Join nodes vào channel
./network channel up
```

### Bước 5: Deploy Chaincode

```bash
# Deploy chaincode example
./network chaincode deploy asset-transfer-basic ../asset-transfer-basic/chaincode-java 1

# Commit chaincode
./network chaincode commit asset-transfer-basic 1
```

### Bước 6: Test Chaincode

```bash
# Khởi tạo ledger với dữ liệu mẫu
./network chaincode invoke asset-transfer-basic '{"Args":["InitLedger"]}'

# Query một asset
./network chaincode query asset-transfer-basic '{"Args":["ReadAsset","asset1"]}'

# Tạo asset mới
./network chaincode invoke asset-transfer-basic '{"Args":["CreateAsset","asset10","blue","20","Tom","1000"]}'

# Query tất cả assets
./network chaincode query asset-transfer-basic '{"Args":["GetAllAssets"]}'
```

### Bước 7: Dọn Dẹp

```bash
# Tắt mạng Fabric
./network down

# Xóa KIND cluster
./network unkind
```

---

## Các Lệnh Thường Dùng

### Quản Lý Cluster

```bash
# Tạo KIND cluster
./network kind

# Xóa KIND cluster
./network unkind

# Khởi tạo cluster infrastructure
./network cluster init

# Clean cluster (không xóa cluster)
./network cluster clean
```

### Quản Lý Mạng

```bash
# Khởi động mạng
./network up

# Tắt mạng
./network down

# Xem trạng thái pods
kubectl get pods -n <namespace>

# Xem logs của một pod
kubectl logs -n <namespace> <pod-name>

# Xem logs real-time
kubectl logs -n <namespace> <pod-name> -f
```

### Debug và Monitoring

```bash
# Xem network log
tail -f network.log

# Xem debug log
tail -f network-debug.log

# Cài đặt monitoring stack (Prometheus + Grafana)
./network monitoring

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Mở browser: http://localhost:3000
# Default credentials: admin/admin
```

---

## Quản Lý Channel

### Tạo Channel Mới

```bash
# 1. Tạo org admins
./network channel create-org-admin

# 2. Tạo channel MSP
./network channel create-channel-msp

# 3. Tạo genesis block
./network channel create-genesis-block

# 4. Join nodes
./network channel up
```

### Join Peer Vào Channel

```bash
# Join một peer cụ thể
./network channel join-peer <org-name> <peer-index>

# Ví dụ: Join peer2 của bank
./network channel join-peer bank 2
```

### Join Orderer Vào Channel

```bash
./network channel join-orderer <orderer-name>

# Ví dụ
./network channel join-orderer orderer1
```

### Update Channel Configuration

```bash
# 1. Fetch current config
./network channel fetch-config

# 2. Get và modify config
./network channel get-modify-config
# (Chỉnh sửa file modified_config.json)

# 3. Create update envelope
./network channel create-config-update-envelope

# 4. Sign bởi các orgs (tùy policy)
./network channel sign bank
./network channel sign land

# 5. Submit update
./network channel update-config bank
```

---

## Quản Lý Chaincode

### Deploy Chaincode Mới

```bash
# Syntax: ./network chaincode deploy <name> <path> <sequence>
./network chaincode deploy my-chaincode ../path/to/chaincode 1

# Commit chaincode
./network chaincode commit my-chaincode 1
```

### Upgrade Chaincode

```bash
# Deploy với sequence cao hơn
./network chaincode deploy my-chaincode ../path/to/chaincode 2

# Commit version mới
./network chaincode commit my-chaincode 2
```

### Invoke Chaincode

```bash
# Syntax: ./network chaincode invoke <name> '<json-args>'
./network chaincode invoke asset-transfer-basic '{"Args":["CreateAsset","asset11","red","15","Alice","2000"]}'
```

### Query Chaincode

```bash
# Syntax: ./network chaincode query <name> '<json-args>'
./network chaincode query asset-transfer-basic '{"Args":["ReadAsset","asset11"]}'
```

### Các Lệnh Chaincode Khác

```bash
# Package chaincode
./network chaincode package my-chaincode my-label ../path/to/chaincode

# Install chaincode
./network chaincode install my-chaincode ../path/to/package.tgz

# Approve chaincode
./network chaincode approve my-chaincode 1

# Query chaincode metadata
./network chaincode metadata my-chaincode
```

---

## Quản Lý Tổ Chức

### Thêm Peer Mới

```bash
# Syntax: ./network add-peer <org> <peer-index>
./network add-peer bank 3

# Điều này sẽ:
# 1. Generate peer YAML file
# 2. Tạo local MSP cho peer
# 3. Launch peer container
```

### Join Peer Mới Vào Channel

```bash
./network channel join-peer bank 3
```

### Thêm Organization Mới

**Bước 1: Update env.sh**
```bash
vim env.sh

# Thêm org vào danh sách
ENV_ORG_NAMES="bank land neworg"
ENV_ORGS_IN_CHANNEL="bank land neworg"
```

**Bước 2: Generate configs**
```bash
./network generate-kube
```

**Bước 3: Restart mạng**
```bash
./network down
./network up
```

**Bước 4: Update channel để thêm org**
```bash
# Generate org config
./network org generate-org-config neworg

# Generate update config
./network org generate-update-config-add-new-org neworg

# Sign và submit (theo hướng dẫn channel update)
```

---

## Troubleshooting

### Pod Không Start

```bash
# Check pod status
kubectl get pods -n <namespace>

# Describe pod để xem events
kubectl describe pod -n <namespace> <pod-name>

# Check logs
kubectl logs -n <namespace> <pod-name>

# Check previous logs nếu pod restart
kubectl logs -n <namespace> <pod-name> --previous
```

### CA Connection Issues

```bash
# Triệu chứng: Connection refused to CA
# Giải pháp: Đợi thêm 10-15 giây sau khi CA start

# Check CA logs
kubectl logs -n <namespace> <org>-ca-<pod-id>

# Test CA connection
curl -k https://<org>-ca.<domain>:<port>/cainfo
```

### Certificate Issues

```bash
# Check certificates trong temp directory
ls -la /build/enrollments/<org>/users/

# Verify certificate content
openssl x509 -in certificate.pem -text -noout

# Check certs trong container
kubectl exec -n <namespace> deploy/<org>-peer1 -- \
  ls -la /var/hyperledger/fabric/organizations/
```

### Channel Join Failures

```bash
# Check orderer logs
kubectl logs -n <namespace> <orderer-name>-<pod-id>

# Check peer logs
kubectl logs -n <namespace> <org>-peer1-<pod-id>

# Verify genesis block tồn tại
ls -la /build/<channel-name>/<channel-name>_genesis_block.pb
```

### Chaincode Issues

```bash
# Check chaincode container logs (if using k8s builder)
kubectl logs -n <namespace> <chaincode-name>-<pod-id>

# Check peer logs for chaincode errors
kubectl logs -n <namespace> <org>-peer1-<pod-id> | grep <chaincode-name>

# Verify chaincode installed
kubectl exec -n <namespace> deploy/<org>-peer1 -- \
  peer lifecycle chaincode queryinstalled

# Check commit readiness
kubectl exec -n <namespace> deploy/<org>-peer1 -- \
  peer lifecycle chaincode checkcommitreadiness \
    --channelID <channel-name> \
    --name <chaincode-name> \
    --version 1.0 \
    --sequence <sequence>
```

### Network Performance Issues

```bash
# Check resource usage
kubectl top pods -n <namespace>
kubectl top nodes

# Check persistent volume status
kubectl get pv
kubectl get pvc -n <namespace>

# Check network policies
kubectl get networkpolicies -n <namespace>
```

### Clean Start (Reset Hoàn Toàn)

```bash
# 1. Xóa mạng
./network down

# 2. Xóa cluster
./network unkind

# 3. Clean local files
rm -rf build/
rm -rf kube/
rm -rf config/
rm -rf network.log network-debug.log

# 4. Start lại từ đầu
./network kind
./network cluster init
./network generate-kube
./network up
```

---

## Tips và Best Practices

### Development

1. **Sử dụng ENV_NUM_ORDERERS=1 cho development**
   - Nhanh hơn, ít resource hơn
   - Production nên dùng 3 hoặc 5

2. **Check logs thường xuyên**
   ```bash
   tail -f network.log       # Workflow status
   tail -f network-debug.log # Detailed info
   ```

3. **Backup cấu hình quan trọng**
   ```bash
   cp env.sh env.sh.backup
   tar -czf config-backup.tar.gz build/ kube/ config/
   ```

### Production

1. **Sử dụng domain thật thay vì localho.st**
   ```bash
   ENV_DOMAIN=blockchain.example.com
   ```

2. **Enable monitoring**
   ```bash
   ./network monitoring
   ```

3. **Backup ledger data định kỳ**
   ```bash
   kubectl exec -n <namespace> deploy/<org>-peer1 -- \
     tar -czf /tmp/ledger-backup.tar.gz /var/hyperledger/production
   kubectl cp <namespace>/<pod>:/tmp/ledger-backup.tar.gz ./ledger-backup.tar.gz
   ```

4. **Monitor resource usage**
   ```bash
   kubectl top pods -n <namespace>
   ```

### Security

1. **Thay đổi CA admin password**
   - Đừng dùng default rcaadmin/rcaadminpw trong production

2. **Enable TLS cho tất cả connections**
   - Already enabled by default

3. **Rotate certificates định kỳ**
   - Use cert-manager auto-renewal

4. **Backup private keys securely**
   - Store trong vault hoặc encrypted storage

---

## Tài Liệu Bổ Sung

### Trong Repository

- [README.md](README.md) - Hướng dẫn cơ bản
- [ARCHITECTURE.md](ARCHITECTURE.md) - Kiến trúc chi tiết
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) - Hướng dẫn cho developers
- [CODE_ANALYSIS.md](CODE_ANALYSIS.md) - Phân tích source code

### External Resources

- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Fabric CA Documentation](https://hyperledger-fabric-ca.readthedocs.io/)
- [KIND Documentation](https://kind.sigs.k8s.io/)

---

## Hỗ Trợ

Nếu bạn gặp vấn đề hoặc có câu hỏi:

1. Kiểm tra logs: `network.log` và `network-debug.log`
2. Tham khảo [Troubleshooting](#troubleshooting) section
3. Đọc documentation chi tiết trong các file .md
4. Open issue trên GitHub repository

---

## Kết Luận

Trust Com Network cung cấp một cách đơn giản và mạnh mẽ để deploy Hyperledger Fabric trên Kubernetes. Với các lệnh được tối ưu hóa và documentation đầy đủ, bạn có thể nhanh chóng khởi động một mạng blockchain cho cả development và production.

**Workflow cơ bản:**
1. ⚙️ Configure (env.sh)
2. 📝 Generate (./network generate-kube)
3. 🚀 Deploy (./network up)
4. 🔗 Create Channel (./network channel ...)
5. 📦 Deploy Chaincode (./network chaincode deploy ...)
6. ✅ Test và Use

Chúc bạn thành công với Trust Com Network! 🎉
