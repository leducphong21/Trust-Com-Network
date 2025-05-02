/*
 * Copyright IBM Corp. All Rights Reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');
const path = require('path');

const channelName = envOrDefault('CHANNEL_NAME', 'mychannel');
const chaincodeName = envOrDefault('CHAINCODE_NAME', 'asset-transfer-basic');
const connectionProfilePath = envOrDefault('CONNECTION_PROFILE_PATH', path.resolve(__dirname, '..', 'org1_ccp.json'));
const walletPath = envOrDefault('WALLET_PATH', path.resolve(__dirname, '..', 'wallet'));
const userId = envOrDefault('USER_ID', 'appuser_org1');

const assetId = `asset${String(Date.now())}`;

async function main() {
    displayInputParameters();

    // Kiểm tra sự tồn tại của connection profile
    try {
        fs.accessSync(connectionProfilePath, fs.constants.R_OK);
    } catch (error) {
        console.error(`Không tìm thấy tệp connection profile tại: ${connectionProfilePath}`);
        process.exit(1);
    }

    // Tải connection profile
    const ccp = JSON.parse(fs.readFileSync(connectionProfilePath, 'utf8'));

    // Tạo wallet
    const wallet = await Wallets.newFileSystemWallet(walletPath);

    // Kiểm tra danh tính người dùng
    const identity = await wallet.get(userId);
    if (!identity) {
        console.error(`Danh tính ${userId} không tồn tại trong wallet. Vui lòng chạy enrollUser.js trước.`);
        process.exit(1);
    }

    // Tạo gateway
    const gateway = new Gateway();
    try {
        await gateway.connect(ccp, {
            wallet,
            identity: userId,
            discovery: { enabled: false, asLocalhost: false },
        });

        // Lấy network và contract
        const network = await gateway.getNetwork(channelName);
        const contract = network.getContract(chaincodeName);

        console.log("contract", contract)

        // Khởi tạo ledger
        await initLedger(contract);

        // Lấy tất cả tài sản
        await getAllAssets(contract);

        // Tạo tài sản mới
        await createAsset(contract);

        // Chuyển giao tài sản
        await transferAsset(contract);

        // Đọc tài sản theo ID
        await readAssetByID(contract);

        // Cập nhật tài sản không tồn tại
        await updateNonExistentAsset(contract);
    } finally {
        await gateway.disconnect();
    }
}

async function initLedger(contract) {
    console.log(
        '\n--> Submit Transaction: InitLedger, function creates the initial set of assets on the ledger'
    );

    await contract.submitTransaction('InitLedger');

    console.log('*** Transaction committed successfully');
}

async function getAllAssets(contract) {
    console.log(
        '\n--> Evaluate Transaction: GetAllAssets, function returns all the current assets on the ledger'
    );

    const result = await contract.evaluateTransaction('GetAllAssets');
    const resultJson = JSON.parse(result.toString());
    console.log('*** Result:', resultJson);
}

async function createAsset(contract) {
    console.log(
        '\n--> Submit Transaction: CreateAsset, creates new asset with ID, Color, Size, Owner and AppraisedValue arguments'
    );

    await contract.submitTransaction(
        'CreateAsset',
        assetId,
        'yellow',
        '5',
        'Tom',
        '1300'
    );

    console.log('*** Transaction committed successfully');
}

async function transferAsset(contract) {
    console.log(
        '\n--> Submit Transaction: TransferAsset, updates existing asset owner'
    );

    await contract.submitTransaction('TransferAsset', assetId, 'Saptha');
    console.log('*** Transaction committed successfully');
}

async function readAssetByID(contract) {
    console.log(
        '\n--> Evaluate Transaction: ReadAsset, function returns asset attributes'
    );

    const result = await contract.evaluateTransaction('ReadAsset', assetId);
    const resultJson = JSON.parse(result.toString());
    console.log('*** Result:', resultJson);
}

async function updateNonExistentAsset(contract) {
    console.log(
        '\n--> Submit Transaction: UpdateAsset asset70, asset70 does not exist and should return an error'
    );

    try {
        await contract.submitTransaction(
            'UpdateAsset',
            'asset70',
            'blue',
            '5',
            'Tomoko',
            '300'
        );
        console.log('******** FAILED to return an error');
    } catch (error) {
        console.log('*** Successfully caught the error: \n', error);
    }
}

function envOrDefault(key, defaultValue) {
    return process.env[key] || defaultValue;
}

function displayInputParameters() {
    console.log(`channelName:       ${channelName}`);
    console.log(`chaincodeName:     ${chaincodeName}`);
    console.log(`connectionProfilePath: ${connectionProfilePath}`);
    console.log(`walletPath:        ${walletPath}`);
    console.log(`userId:            ${userId}`);
}

main().catch((error) => {
    console.error('******** FAILED to run the application:', error);
    console.error(error.stack);
    process.exitCode = 1;
});