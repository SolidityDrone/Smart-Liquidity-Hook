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


interface AavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;
    
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);
}

interface AToken {
      function balanceOf(address account) external view returns (uint256);
}

contract CLSmartLiquidityHooktest is Script, Test, CLTestUtils{
    using CLPoolParametersHelper for bytes32;
    using PoolIdLibrary for PoolKey;
    
    address internal brevisRequest = 0x841ce48F9446C8E281D3F1444cB859b4A6D0738C;
    address internal cLPoolManagerAddress = 0x6F9302eE8760c764d775B1550C65468Ec4C25Dfc;
    address internal sepoliaAavePoolProxyAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal sepoliaPoolDataProvider = 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31;
    bytes32 internal vkHash = bytes32(0);

    PoolKey key;
    Currency currency0;
    Currency currency1;    
    CLSmartLiquidityHook internal hook;
    
    function setUp() public {
        (currency0, currency1) = deployContractsWithTokens();
        hook = new CLSmartLiquidityHook(
            poolManager,
            sepoliaAavePoolProxyAddress, 
            positionManager, 
            permit2, 
            universalRouter, 
            brevisRequest, 
            sepoliaPoolDataProvider
            );
        deal(sepoliaUSDC, address(this), 101_000e6);
        deal(sepoliaUSDT, address(this), 101_000e6);
        
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: uint24(100), 
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
        
        CLSmartLiquidityHook.AddLiquidityParams memory params = CLSmartLiquidityHook.AddLiquidityParams({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(100),
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
            amount0Desired: 1_000e6,
            amount1Desired: 1_000e6,
            amount0Min: 1,  // naive
            amount1Min: 1, // naive
            to: address(this),
            deadline: block.timestamp + 180 seconds
        });  
        permit2.approve(address(sepoliaUSDC), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(sepoliaUSDT), address(positionManager), type(uint160).max, type(uint48).max);
        bytes memory encodedParams = abi.encode(params);
               
        IERC20(sepoliaUSDC).approve(address(hook), type(uint).max);
        IERC20(sepoliaUSDT).approve(address(hook), type(uint).max);
        poolManager.initialize(key, Constants.SQRT_RATIO_1_1, encodedParams);
        hook.setVkHash(vkHash);

    }

    // function testAddLiquidityAndBorrowToYield() public {
    //     CLSmartLiquidityHook.AddLiquidityParams memory params = CLSmartLiquidityHook.AddLiquidityParams({
    //         currency0: currency0,
    //         currency1: currency1,
    //         fee: uint24(100),
    //         parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
    //         amount0Desired: 100_000e6,
    //         amount1Desired: 100_000e6,
    //         amount0Min: 1,  // naive
    //         amount1Min: 1, // naive
    //         to: address(this),
    //         deadline: block.timestamp + 180 seconds
    //     });

    //     IERC20(sepoliaUSDC).approve(address(hook), type(uint).max);
    //     IERC20(sepoliaUSDT).approve(address(hook), type(uint).max);
        

    //     hook.addLiquidity(params);

        
    //     address aUsdcToken = 0x16dA4541aD1807f4443d92D26044C1147406EB80;
    //     uint aBalance = AToken(aUsdcToken).balanceOf(address(hook));
        
    //     console.log("Aave Token Balance before borrow simulation: ");
    //     console.logUint(aBalance);
    //     BorrowOnAave();
    //     vm.warp(block.timestamp + 30 days);
    //     aBalance = AToken(aUsdcToken).balanceOf(address(hook));
    //     console.log("Aave Token Balance after borrow simulation: ");
    //     console.logUint(aBalance);
    // }
    

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
            deadline: block.timestamp + 180 seconds
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
        exactInputSingle(params);
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

    function testWithdrawLiquidity() public {
        console.log("Balances before adding liquidity: ");
        console.logUint(IERC20(sepoliaUSDC).balanceOf(address(this)));
        console.logUint(IERC20(sepoliaUSDT).balanceOf(address(this)));
        testAddLiquidity();
        console.log("Balances after adding liquidity: ");
        console.logUint(IERC20(sepoliaUSDC).balanceOf(address(this)));
        console.logUint(IERC20(sepoliaUSDT).balanceOf(address(this)));
        address liquidityERC20 = address(hook.liquidityToken());
        uint currentLiquidityBalance = IERC20(liquidityERC20).balanceOf(address(this));
        
        CLSmartLiquidityHook.RemoveLiquidityParams memory params = CLSmartLiquidityHook.RemoveLiquidityParams({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(100),
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
            liquidity: currentLiquidityBalance,
            deadline: block.timestamp
        });

        hook.removeLiquidity(params);
        console.log("Balances after pulling back liquidity: ");
        console.logUint(IERC20(sepoliaUSDC).balanceOf(address(this)));
        console.logUint(IERC20(sepoliaUSDT).balanceOf(address(this)));
    }

    function testHandlingBrevisOutputDecoding() public {        
        (uint contribution, address contributor, uint lastLiquidity, uint lastTimestamp) =
            hook.decodeOutput(
                abi.encodePacked(uint248(555), address(this), uint248(500), uint248(block.timestamp - 1 days))
            );
        assertEq(contribution, 555);
        assertEq(contributor, address(this));
        assertEq(lastLiquidity, uint248(500));
        assertEq(lastTimestamp, uint248(block.timestamp - 1 days));
    }

    function BorrowOnAave() internal {
        address bob = address(2);
        deal(sepoliaUSDC, bob, 10e28);
        // approve aave
        vm.prank(bob);
        IERC20(sepoliaUSDC).approve(sepoliaAavePoolProxyAddress, 100_000e6);
        // supply some usdc
        vm.prank(bob);
        AavePool(sepoliaAavePoolProxyAddress).supply(sepoliaUSDC, 100_000e6, address(bob), uint16(0));
        // borrow 
        vm.prank(bob);
        AavePool(sepoliaAavePoolProxyAddress).borrow(sepoliaUSDC, 10_000e6, 2, uint16(0), address(bob));
        // approve usdc before rapaying
        vm.prank(bob);
        IERC20(sepoliaUSDC).approve(sepoliaAavePoolProxyAddress, 10_000e6);
        // repay 
        vm.prank(bob);
        AavePool(sepoliaAavePoolProxyAddress).repay(sepoliaUSDC, 10_000e6, 2, address(bob));
    }

    function testBrevisCallback() public {
        // add liquidity so that we can start accruing contribution points
        testAddLiquidity();
        // borrow on aave and warp to simulate yield accruing
        BorrowOnAave();
        vm.warp(block.timestamp + 30 days);

        address liquidityERC20 = address(hook.liquidityToken());
        // get liquidity from liquidity token balance
        uint currentLiquidityBalance = IERC20(liquidityERC20).balanceOf(address(this));
        
        CLSmartLiquidityHook.RemoveLiquidityParams memory params = CLSmartLiquidityHook.RemoveLiquidityParams({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(100),
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
            liquidity: currentLiquidityBalance,
            deadline: block.timestamp
        });
        // remove liquidity
        hook.removeLiquidity(params);


        // declare a mocked output from brevis circuit
        bytes memory appCircuitOutputMock = abi.encodePacked(uint248(555), address(this), uint248(500), uint248(block.timestamp - 1 days));

        vm.prank(brevisRequest);
        hook.brevisCallback(vkHash, appCircuitOutputMock);
        console.log("User balance after withdrawing liquidity and claim its rewards trough brevis");
        console.log(IERC20(sepoliaUSDC).balanceOf(address(this)));
    }
}
