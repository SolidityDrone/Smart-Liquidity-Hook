// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


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

    function setUp() public {
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
      
    }

    function testAddLiquidity() public {
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
    }
    

    function testLowPriceImpactSwap() public {
        testAddLiquidity();
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint160 sqrtPriceLimitX96 = uint160(uint256(sqrtPriceX96) * 1000 / 1005); 
        
        ICLRouterBase.CLSwapExactInputSingleParams memory params = ICLRouterBase.CLSwapExactInputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountIn: 10e6,
            amountOutMinimum: 0, // naive 
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            hookData: hex''
        });
        console.log(IERC20(sepoliaUSDC).balanceOf(address(poolManager)));
        console.log(IERC20(sepoliaUSDT).balanceOf(address(poolManager)));
        exactInputSingle(params);
        console.log(IERC20(sepoliaUSDC).balanceOf(address(poolManager)));
        console.log(IERC20(sepoliaUSDT).balanceOf(address(poolManager)));
    }
    

    function testHighPriceImpactSwap() public {
        testAddLiquidity();
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint160 sqrtPriceLimitX96 = uint160(uint256(sqrtPriceX96) * 1000 / 1005); 

        ICLRouterBase.CLSwapExactInputSingleParams memory params = ICLRouterBase.CLSwapExactInputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountIn: 50_000e6,
            amountOutMinimum: 0, // naive 
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            hookData: hex''
        });
      
        exactInputSingle(params);
    }

    // function testWithdrawLiquidity() public {
    //     console.logUint(IERC20(sepoliaUSDC).balanceOf(address(this)));
    //     console.logUint(IERC20(sepoliaUSDT).balanceOf(address(this)));
    //     testAddLiquidity();
    //     console.logUint(IERC20(sepoliaUSDC).balanceOf(address(this)));
    //     console.logUint(IERC20(sepoliaUSDT).balanceOf(address(this)));
    //     address liquidityERC20 = address(hook.liquidityToken());
    //     uint currentLiquidityBalance = IERC20(liquidityERC20).balanceOf(address(this));
        
    //     CLSmartLiquidityHook.RemoveLiquidityParams memory params = CLSmartLiquidityHook.RemoveLiquidityParams({
    //         currency0: currency0,
    //         currency1: currency1,
    //         fee: uint24(100),
    //         parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
    //         liquidity: currentLiquidityBalance,
    //         deadline: block.timestamp
    //     });

    
    //     hook.removeLiquidity(params);
    //     console.logUint(IERC20(sepoliaUSDC).balanceOf(address(this)));
    //     console.logUint(IERC20(sepoliaUSDT).balanceOf(address(this)));

    // }

}
