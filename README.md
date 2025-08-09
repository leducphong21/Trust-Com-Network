# Trust Com Network

 The Trust Com Network is a solution for deploying and managing Hyperledger Fabric networks on Kubernetes. It simplifies the setup, development, and operation of blockchain networks through a streamlined, one-click deployment process and comprehensive operational commands. This guide provides instructions for quick setup and ongoing network management in both development and production environments.

### Objectives:
- One-Command Setup: Enable rapid deployment of a Hyperledger Fabric network with a single command.
- Production Reference: Offer a guide for deploying production-style networks on Kubernetes.
- Development Platform: Provide a cloud-ready environment for developing smart contract, Fabric Gateway, and blockchain applications.
- Fabric CA ( Certificate Authority ) Supplement: Extend the Fabric CA Operations and Deployment guides with Kubernetes-specific configurations.
- Platform Flexibility: Run on any Kubernetes cluster, including KIND, Rancher Desktop, or other K8s platforms.

### Operational Support
##### Beyond one-command setup, Trust Com Network provides robust tools for ongoing network operations:
- Peer Management: Dynamically add or join peers to channels, enabling network scaling.
- Channel Management: Create, modify, and update channel configurations to adapt to changing requirements.
- Smart Contract Lifecycle: Deploy, invoke, and query smart contract with simplified commands.
- Kubernetes Integration: Leverage Kubernetes for resilient, cloud-ready network deployment and management.

## Prerequisites:

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://stedolan.github.io/jq/)
- [envsubst](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) (`brew install gettext` on OSX)

- K8s - either:
  - [KIND](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) + [Docker](https://www.docker.com) (resources: 8 CPU / 8 GRAM) 

## Quickstart 

```shell
cd trust-com-network
cp env.example.sh env.sh
./network generate-kube
```

Create a KIND cluster:  
```shell
./network kind
./network cluster init
```


Launch the network, create a channel, and deploy the [basic-asset-transfer](../asset-transfer-basic) smart contract: 
```shell

./network up

./network channel create-org-admin

./network channel create-channel-msp

./network channel create-genesis-block

./network channel up

./network chaincode deploy asset-transfer-basic ../asset-transfer-basic/chaincode-java 1

./network chaincode commit asset-transfer-basic 1
```

Invoke and query chaincode:
```shell
./network chaincode invoke asset-transfer-basic '{"Args":["InitLedger"]}'
./network chaincode query  asset-transfer-basic '{"Args":["ReadAsset","asset1"]}'
```

Shut down the trust com network 
```shell
./network down 
```

Tear down the cluster (KIND): 
```shell
./network unkind
```

For Rancher: Preferences -> Kubernetes Settings -> Reset Kubernetes  OR ...
```shell
./network cluster clean
```

## Available ORG Commands
Generate a config update to add a new org
```shell
./network org generate-org-config <org>
```

Generate config update to add a new org
```shell
./network org generate-update-config-add-new-org <org_name>
```


## Available Peer Commands
Creates a new peer and luanch peer to k8s
```shell
./network add-peer <org> <peer-index>
```

## Available Chaincode Commands
Deploy chaincode
```shell
./network chaincode deploy <chaincode_name> <chaincode_path> <sequense>
```

Commit chaincode
```shell
./network chaincode commit <chaincode_name> <sequense>
```

## Available Channel Commands
Create Genesis Block
```shell
./network channel create-genesis-block
```

Join orderers and peers to the created channel to bring it into operation.
```shell
./network channel up
```

Join peer to channel.
```shell
./network channel join-peer <org> <peer-index>
```

Fetch Channel Configuration
```shell
./network channel fetch-config
```

Get and Modify Channel Configuration
```shell
./network channel get-modify-config
```

Create Configuration Update Envelope
```shell
./network channel create-config-update-envelope
```

Signs the configuration update envelope using the specified organization's credentials.
```shell
./network channel sign <org>
```

Submits the signed configuration update envelope to the channel.
```shell
./network channel update-config <org>
```

## Available Setup Monitoring Commands
Install monitoring with prometheus and grafana
```shell
./network monitoring
```
