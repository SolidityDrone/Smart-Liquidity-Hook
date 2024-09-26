
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



