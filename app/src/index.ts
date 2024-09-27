import { ethers } from 'ethers';
import { Brevis, ErrCode, Field, ProofRequest, Prover, ReceiptData } from 'brevis-sdk-typescript';

async function main() {
    console.log("Started script");
    
    // Initialize Prover and Brevis instances
    const prover = new Prover('localhost:33247');
    const brevis = new Brevis('appsdkv2.brevis.network:9094');

    const proofReq = new ProofRequest();
    
    // Set up Ethers.js provider for Ethereum mainnet
    const provider = new ethers.providers.JsonRpcProvider("https://ethereum-rpc.publicnode.com");

    // Example ERC20 contract address
    const tokenAddress = "0x5698bad447b8453e698e2c5992530f6764aa795e"; // Replace with the token contract address

    // Event signature for the Transfer event
    const transferEventSignature = "Transfer(address,address,uint256)";
    const transferEventTopic = ethers.utils.id(transferEventSignature);

    // The address you want to filter by
    const addressToCheck = "0xa62eeb0e29007c75130bcf74a128e524d8ecbb10";
    const callbackAddress = "0xeec66d9b615ff84909be1cb1fe633cc26150417d";
    
    // Define block range parameters
    const startBlock = 20125423; // Starting block
    const endBlock = await provider.getBlockNumber(); // Latest block number
    const range = 50000; // Max range per request
    let foundEvent = false; // Flag to track if any event is found

    for (let fromBlock = startBlock; fromBlock < endBlock; fromBlock += range) {
        const toBlock = Math.min(fromBlock + range - 1, endBlock); // Calculate the toBlock
        console.log(`Fetching logs from block ${fromBlock} to ${toBlock}`);

        // Define the filter for the logs
        const filter = {
            address: tokenAddress,
            topics: [
                transferEventTopic, // Event signature
                null,                // "from" address is not filtered
                ethers.utils.hexZeroPad(addressToCheck, 32) // "to" address, padded to 32 bytes
            ],
            fromBlock: ethers.utils.hexValue(fromBlock), // Convert to hex
            toBlock: ethers.utils.hexValue(toBlock) // Convert to hex
        };

        // Fetch logs for the current block range
        const logsBatch = await provider.getLogs(filter);
        
        if (logsBatch.length > 0) {
            foundEvent = true; // Set the flag to true if any event is found

            // Process the first log found
            const log = logsBatch[0]; // Get the first log
            const blockNumber = log.blockNumber; // Save the block number
            const toAddress = `0x${log.topics[2].slice(26)}`; // Extracting 'to' address from topics
            const fromAddress = `0x${log.topics[1].slice(26)}`; // Extracting 'from' address from topics
            const logIndex = log.logIndex; // Log index from the log
            const txHash = log.transactionHash; // Extract transaction hash
        
            // Ensure logIndex and addresses are valid before creating receipt
            if (logIndex !== undefined && logIndex !== null && fromAddress && toAddress) {
                console.log("Adding Receipt with value:", toAddress.toLowerCase());
                proofReq.addReceipt(
                    new ReceiptData({
                        block_num: blockNumber, // Save block number
                        tx_hash: txHash, // Add transaction hash
                        fields: [
                            new Field({
                                contract: tokenAddress,
                                log_index: 0, // Use logIndex to track the position of the log
                                event_id: transferEventTopic,
                                is_topic: true,  // 'to' address is in topic
                                field_index: 2,  // 1st indexed parameter is the receiver
                                value: toAddress, // Default to zero address if empty
                            })
                        ]
                    })
                );
                proofReq.addReceipt(
                    new ReceiptData({
                        block_num: blockNumber, // Save block number
                        tx_hash: "0x7ed95031c9c0682640042c2a5614f7dfc1af957039c435717724e35b02aa3fda", // Add transaction hash
                        fields: [
                            new Field({
                                contract: tokenAddress,
                                log_index: 0, // Use logIndex to track the position of the log
                                event_id: transferEventTopic,
                                is_topic: true,  // 'to' address is in topic
                                field_index: 2,  // 1st indexed parameter is the receiver
                                value: toAddress, // Default to zero address if empty
                            })
                        ]
                    })
                );
        
                // Output the first event found
                console.log("First Filtered Transfer Event:");
                console.log({
                    blockNumber: blockNumber,
                    to: toAddress,
                    txHash: txHash // Log the transaction hash
                });
            }
        }
    }

    if (!foundEvent) {
        console.log("No events found for the specified address in the specified block range.");
        return; // Exit if no events were found
    }
    
    const proofRes = await prover.prove(proofReq);
    console.log("Getting proof result . . .")
    // Error handling
    if (proofRes.has_err) {
        const err = proofRes.err;
        switch (err.code) {
            case ErrCode.ERROR_INVALID_INPUT:
                console.error('Invalid receipt/storage/transaction input:', err.msg);
                break;

            case ErrCode.ERROR_INVALID_CUSTOM_INPUT:
                console.error('Invalid custom input:', err.msg);
                break;

            case ErrCode.ERROR_FAILED_TO_PROVE:
                console.error('Failed to prove:', err.msg);
                break;
        }
        return;
    }

    console.log('Proof:', proofRes.proof);

    try {
        const brevisRes = await brevis.submit(proofReq, proofRes, 1, 11155111, 1, "", callbackAddress);
        console.log('Brevis Response:', brevisRes);

        await brevis.wait(brevisRes.queryKey, 11155111);
    } catch (err) {
        console.error(err);
    }
}

// Execute the main function
main().catch(error => {
    console.error(error);
});
