// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

<<<<<<< HEAD
=======

>>>>>>> acdef9c91aec3a4ed6e3fb465a73c3fb3376c6a3
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";
import {CLSmartLiquidityHook} from "../src/CL-Pool/CLSmartLiquidityHook.sol";
import {ICLPoolManager} from "pancake-v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Constants} from "pancake-v4-core/test/pool-cl/helpers/Constants.sol";
import {Currency} from "pancake-v4-core/src/types/Currency.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {CLTestUtils} from "./utils/CLTestUtils.sol";
import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {ICLRouterBase} from "pancake-v4-periphery/src/pool-cl/interfaces/ICLRouterBase.sol";
import {PoolId, PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
<<<<<<< HEAD


contract CounterScript is Script {

    address internal sepoliaCLPositionManager = 0x969D90aC74A1a5228b66440f8C8326a8dA47A5F9;
    address internal sepoliaAavePool = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    /*
        

    */
    CLSmartLiquidityHook internal hook;
    function setUp() public {}

    function run() public {
        vm.broadcast();
        hook = new CLSmartLiquidityHook(ICLPoolManager(sepoliaCLPositionManager), sepoliaAavePool);
    }
=======

contract CLSmartLiquidityHooktest is Script, Test, CLTestUtils{
    using CLPoolParametersHelper for bytes32;
    using PoolIdLibrary for PoolKey;
    
    address internal brevisRequest = 0x841ce48F9446C8E281D3F1444cB859b4A6D0738C;
    address internal cLPoolManagerAddress = 0x08F012b8E2f3021db8bd2A896A7F422F4041F131;
    address internal sepoliaAavePoolAddres = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    PoolKey key;
    Currency currency0;
    Currency currency1;    
    CLSmartLiquidityHook internal hook;

    function setup() public {}

    function deploy() public {
        vm.startBroadcast();
        (currency0, currency1) = deployContractsWithTokens();
        hook = new CLSmartLiquidityHook(poolManager, sepoliaAavePoolAddres, positionManager, permit2, universalRouter, brevisRequest);
        deal(sepoliaUSDC, address(this), 1e30);
        deal(sepoliaUSDT, address(this), 1e30);
        
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: uint24(100), 
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });

        poolManager.initialize(key, Constants.SQRT_RATIO_1_1, new bytes(0));


          CLSmartLiquidityHook.AddLiquidityParams memory params = CLSmartLiquidityHook.AddLiquidityParams({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(100),
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
            amount0Desired: 100_000e6,
            amount1Desired: 100_000e6,
            amount0Min: 1,  // naive
            amount1Min: 1, // naive
            to: address(this),
            deadline: block.timestamp
        });

        IERC20(sepoliaUSDC).approve(address(hook), type(uint).max);
        IERC20(sepoliaUSDT).approve(address(hook), type(uint).max);
        

        hook.addLiquidity(params);
        vm.stopBroadcast();
    }

   
    

    


    

>>>>>>> acdef9c91aec3a4ed6e3fb465a73c3fb3376c6a3
}
