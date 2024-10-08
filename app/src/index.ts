import { ethers } from 'ethers';
import { Brevis, ErrCode, Field, ProofRequest, Prover, ReceiptData } from 'brevis-sdk-typescript';

async function main() {
    console.log("Started script");

    // Initialize Prover and Brevis instances
    const prover = new Prover('localhost:33247');
    const brevis = new Brevis('appsdkv2.brevis.network:9094');
    const proofReq = new ProofRequest();

    const provider = new ethers.providers.JsonRpcProvider("https://rpc2.sepolia.org");

    const emitter_contract = "0xbA68302DA991Edb4892C047cb845045Dd57812b0"; // Replace with the token contract address

    // Event signatures for the two events
    const addLiqSignature = "LiquidityAdded(address,uint256,uint256)";
    const remLiqSignature = "LiquidityRemoved(address,uint256,uint256)";
    const addLiqEventTopic = ethers.utils.id(addLiqSignature);
    const remLiqEventTopic = ethers.utils.id(remLiqSignature);

    const addressToCheck = "0xCAc3f7c8C771476251e93B44CB7afA0C2eDd5EB0";
    const callbackAddress = "0xeec66d9b615ff84909be1cb1fe633cc26150417d ";

    const startBlock = 6771000;
    const endBlock = await provider.getBlockNumber();
    const range = 50000;

    let allEvents: any[] = []; // Store all events in a single array

    for (let fromBlock = startBlock; fromBlock < endBlock; fromBlock += range) {
        const toBlock = Math.min(fromBlock + range - 1, endBlock);
        console.log(`Fetching logs from block ${fromBlock} to ${toBlock}`);

        // Define the filter for LiquidityAdded events
        const addLiqFilter = {
            address: emitter_contract,
            topics: [
                addLiqEventTopic,
                ethers.utils.hexZeroPad(addressToCheck, 32)
            ],
            fromBlock: ethers.utils.hexValue(fromBlock),
            toBlock: ethers.utils.hexValue(toBlock)
        };

        // Define the filter for LiquidityRemoved events
        const remLiqFilter = {
            address: emitter_contract,
            topics: [
                remLiqEventTopic,
                ethers.utils.hexZeroPad(addressToCheck, 32)
            ],
            fromBlock: ethers.utils.hexValue(fromBlock),
            toBlock: ethers.utils.hexValue(toBlock)
        };

        // Fetch logs for LiquidityAdded and LiquidityRemoved separately
        const logsAdded = await provider.getLogs(addLiqFilter);
        const logsRemoved = await provider.getLogs(remLiqFilter);

        console.log(`Found ${logsAdded.length} LiquidityAdded logs and ${logsRemoved.length} LiquidityRemoved logs in this range.`);

        // Process both logs into events with a 'type' field
        const addLiqEvents = logsAdded.map(log => ({
            ...log,
            eventType: 'LiquidityAdded'
        }));

        const remLiqEvents = logsRemoved.map(log => ({
            ...log,
            eventType: 'LiquidityRemoved'
        }));

        // Combine both event arrays
        allEvents = [...allEvents, ...addLiqEvents, ...remLiqEvents];
    }

    let receiptCounter = 0;

    // Sort the combined events array by the 'time' field
    allEvents.sort((a, b) => {
        const decodedDataA = ethers.utils.defaultAbiCoder.decode(
            ['uint256', 'uint256'], a.data
        );
        const decodedDataB = ethers.utils.defaultAbiCoder.decode(
            ['uint256', 'uint256'], b.data
        );

        // Compare the 'time' field (second field in the event data)
        return decodedDataA[1].toNumber() - decodedDataB[1].toNumber();
    });

    // Process each event and add receipts
    for (const log of allEvents) {
        // Typecasting logIndex
        let logIndex: number;

        // Match type case of logIndex string or number or BigInt and make it number
        switch (typeof log.logIndex) {
            case 'string':
                logIndex = parseInt(log.logIndex);
                break;
            case 'number':
                logIndex = log.logIndex;
                break;
            case 'bigint':
                logIndex = Number(log.logIndex);
                break;
            default:
                throw new Error('Invalid logIndex type');
        }

        // Typecasting blockNumber
        let blockNumber: number;

        // Match type case of block number string or number or BigInt and make it number
        switch (typeof log.blockNumber) {
            case 'string':
                blockNumber = parseInt(log.blockNumber);
                break;
            case 'bigint':
                blockNumber = Number(log.blockNumber);
                break;
            case 'number':
                blockNumber = log.blockNumber;
                break;
            default:
                throw new Error('Invalid block number type');
        }

        const txHash = log.transactionHash;
        const eventType = log.eventType;

        // Extract 'user' address from topics[1]
        const user = `0x${log.topics[1].slice(26)}`;

        // Decode the data field to get liquidity and time
        const decodedData = ethers.utils.defaultAbiCoder.decode(
            ['uint256', 'uint256'], log.data
        );
        const liquidity = decodedData[0];
        const time = decodedData[1];

        console.log(`Adding Receipt for ${eventType} with values:`, {
            user: user,
            liquidity: liquidity.toString(),
            time: time.toString(),
            logIndex: logIndex,
            block: blockNumber,
            hash: txHash
        });

        proofReq.addReceipt(
            new ReceiptData({
                block_num: blockNumber,
                tx_hash: txHash,
                fields: [
                    new Field({
                        contract: emitter_contract,
                        log_index: logIndex,
                        event_id: log.topics[0], // Event signature
                        is_topic: true,  // 'user' address is in topic
                        field_index: 1,  //
                        value: addressToCheck,
                    }),
                    new Field({
                        contract: emitter_contract,
                        log_index: logIndex,
                        event_id: log.topics[0],
                        is_topic: false,  // 'liquidity' is in data
                        field_index: 2,  // Changed to unique index
                        value: liquidity.toString(),
                    }),
                    new Field({
                        contract: emitter_contract,
                        log_index: logIndex,
                        event_id: log.topics[0],
                        is_topic: false,  // 'time' is in data
                        field_index: 3,  // Changed to unique index
                        value: time.toString(),
                    })
                ]
            }),
            receiptCounter // Use receiptCounter here
        );
        // Increment the receipt counter for the next receipt
        receiptCounter++;
        
    }

    
    const proofRes = await prover.prove(proofReq);

    // Error handling
    if (proofRes.has_err) {
        const err = proofRes.err;
        switch (err.code) {
            case ErrCode.ERROR_INVALID_INPUT:
                console.error('invalid receipt/storage/transaction input:', err.msg);
                break;

            case ErrCode.ERROR_INVALID_CUSTOM_INPUT:
                console.error('invalid custom input:', err.msg);
                break;

            case ErrCode.ERROR_FAILED_TO_PROVE:
                console.error('failed to prove:', err.msg);
                break;
        }
        return;
    }
    console.log(proofRes.proof);

    const brevisRes = await brevis.submit(proofReq, proofRes, 11155111, 11155111, 1, "", callbackAddress);
    await brevis.wait(brevisRes.queryKey, 11155111);
}

main().catch(error => {
    console.error(error);
});
