# **Smart Liquidity Hook (SLH)**

**SLH** is a PancakeSwap V4 hook developed to maximize rewards for Liquidity Providers (LPs) in stablecoin pairs such as USDC/USDT. This project introduces a novel mechanism that allows liquidity pools to generate profits from both liquidity provision and lending simultaneously.

## **How It Works**

The SLH keeps 30% of the pool’s capacity as active liquidity to facilitate small trades, while the remaining 70% is deposited into the Aave v3 market to maximize the efficiency of idle liquidity. 

Whenever a trade pushes the price beyond the predefined slippage threshold, the hook automatically withdraws the entire liquidity from Aave to ensure there is sufficient liquidity for a fair swap execution.

Each time liquidity is added or removed, an event is emitted and recorded in a receipt list that is submitted to the Brevis prover. The Brevis circuit computes time-based contribution points, allowing LPs to claim their share of rewards generated while providing liquidity. LPs can unlock their rewards by requesting a Brevis proof, which validates their contribution.

## **Project Structure**
├── app # Frontend and application logic
├── contracts # Foundry folder containing smart contracts 
└── prover # Brevis circuits for proof generation


The project is organized into three main components:
## **Developer Experience**

During development, several challenges were encountered:

- **PancakeSwap V4:** With minimal prior knowledge of PancakeSwap V4, understanding its mechanism was a significant learning experience. One notable issue was the **LockAlreadySet()** error encountered during position modification in a swap. This error comes from the settlement guard (reentrancy guard) mechanism. After investigating, I found the `modifyLiquidityWithNoLock()` function, although figuring out the correct parameters was difficult due to limited documentation. Overall, the experience was rewarding despite the lack of examples.

- **Brevis Integration:** Integrating Brevis was a more difficult task, as I had never worked with Go before. Writing and compiling the circuit took a full day, but I eventually succeeded. Unfortunately, I ran into issues with submitting valid receipts to the Brevis prover service, which I’m still working to resolve.

## **Future Enhancements**

This project is a **Proof of Concept (PoC)**, with many areas for optimization and improvement. Planned enhancements include:

- Supporting multiple keys for better flexibility.
- Optimizing the code for performance and efficiency.
- Adapting the hook to work on other blockchains that support Aave, such as Binance Smart Chain (BSC) and Polygon.

The code will be maintained and improved as time permits.

## **License**

This project is licensed under the MIT License. See the `LICENSE` file for details.
