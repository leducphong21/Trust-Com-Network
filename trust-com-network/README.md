# Trust Com Netowk

### Objectives:

- Provide a simple, _one click_ activity for running the Trust Com Netowk
- Provide a reference guide for deploying _production-style_ networks on Kubernetes.
- Provide a _cloud ready_ platform for developing chaincode, Gateway, and blockchain apps.
- Provide a Kube supplement to the Fabric [CA Operations and Deployment](https://hyperledger-fabric-ca.readthedocs.io/en/latest/deployguide/ca-deploy.html) guides.
- Support a transition to [Chaincode as a Service](https://hyperledger-fabric.readthedocs.io/en/latest/cc_service.html).
- Support a transition from the Internal, Docker daemon to [External Chaincode](https://hyperledger-fabric.readthedocs.io/en/latest/cc_launcher.html) builders.
- Run on any Kube.


## Prerequisites:

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://stedolan.github.io/jq/)
- [envsubst](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) (`brew install gettext` on OSX)

- K8s - either:
  - [KIND](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) + [Docker](https://www.docker.com) (resources: 8 CPU / 8 GRAM) 
  - [Rancher Desktop](https://rancherdesktop.io) (resources: 8 CPU / 8GRAM, mobyd, and disable Traefik)

## Quickstart 

```shell
cp env.example.sh env.sh
./network generate-kube
```

Create a KIND cluster:  
```shell
./network kind
./network cluster init

or for [Rancher / k3s](docs/KUBERNETES.md#rancher-desktop-and-k3s):
```shell
export TEST_NETWORK_CLUSTER_RUNTIME=k3s

./network cluster init
```



Launch the network, create a channel, and deploy the [basic-asset-transfer](../asset-transfer-basic) smart contract: 
```shell

./network up

./network channel create-org-admin

./network channel create-channel-msp

./network channel create

./network chaincode deploy asset-transfer-basic ../asset-transfer-basic/chaincode-java
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

## Available Peer Commands
Creates a new peer and luanch peer to k8s
```shell
./network add-peer <org> <peer-index>
```

## Available Channel Commands
Creates a new channel and joins orderers and peers to it.
```shell
./network channel create
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

kubectl port-forward -n bank svc/bank-peer1 5984:5984
