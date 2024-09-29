## Smart Liquidity Hook Contracts

These contracts are part of the **Smart Liquidity Hook (SLH)** system, designed to optimize liquidity provider rewards in stablecoin pairs like USDC/USDT by simultaneously engaging in both liquidity provision and lending on Aave. The hook dynamically manages liquidity, allocating 70% to Aave to maximize idle capital efficiency while keeping 30% for active trading. When trade slippage exceeds a predefined threshold, the contract automatically withdraws liquidity from Aave to ensure fair swaps.

### Usage
In this repo you can either run the tests or the script. It is important to provide a sepolia fork url when testing, this is mandatory as the contract needs the Aave contracts context from sepolia network.
The currencies used in the test are [USDT](https://sepolia.etherscan.io/token/0xaa8e23fb1079ea71e0a56f48a2aa51851d8433d0) and [USDC](https://sepolia.etherscan.io/token/0x94a9d9ac8a22534e3faca9f4e7f2e2cf85d5e4c8) on sepolia, testnet tokens are available here on [Aave faucet](https://staging.aave.com/faucet/)

### Build

To build the contracts, use the following command:

```shell
$ forge build
```

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test --fork-url https://rpc.sepolia.org --via-ir -vvvvv
```
### Deploy

```shell
$ forge script script/HookInitializer.s.sol --broadcast --rpc-url <your_rpc> --via-ir --optimize --optimizer-runs 10000 --legacy --private-key <your_private_key>
```



