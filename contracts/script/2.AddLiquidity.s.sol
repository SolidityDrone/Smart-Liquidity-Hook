pragma solidity ^0.8.26;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
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

import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {ICLRouterBase} from "pancake-v4-periphery/src/pool-cl/interfaces/ICLRouterBase.sol";
import {PoolId, PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {Vault} from "pancake-v4-core/src/Vault.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {CLPoolManager} from "pancake-v4-core/src/pool-cl/CLPoolManager.sol";
import {CLPositionManager} from "pancake-v4-periphery/src/pool-cl/CLPositionManager.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {UniversalRouter, RouterParameters} from "pancake-v4-universal-router/src/UniversalRouter.sol";


contract AddLiquidity is Script, Test{
    using CLPoolParametersHelper for bytes32;
    using PoolIdLibrary for PoolKey;
    
    address internal sepoliaUSDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    address internal sepoliaUSDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address internal sepoliaPermit2 = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;
    address internal sepoliaVault = 0xA9B361Df352a80BA3213c656b4EfA5436EC80362;
    address internal cLPoolManagerAddress = 0x6F9302eE8760c764d775B1550C65468Ec4C25Dfc;
    address internal sepoliaAavePoolAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal sepoliaPositionManager = 0x969D90aC74A1a5228b66440f8C8326a8dA47A5F9;
    address internal sepoliaUniversalRouter = 0xf342FfB466018938c6251E2CC62Cf6AD8D936cf8;

    address internal deployedHookIstance = 0xc81E0E36E7F78F0636c27B6FbAc1dDc201bFDF4f;

    PoolKey key;
    Currency currency0;
    Currency currency1;    
    CLSmartLiquidityHook internal hook;
    PoolId poolId;

    ERC20 token0;
    ERC20 token1;
    function setUp() public {
        token0 = ERC20(sepoliaUSDC);
        token1 = ERC20(sepoliaUSDT);

        (currency0, currency1) = sort(token0, token1);
        hook = CLSmartLiquidityHook(deployedHookIstance);
    }

    function run() public {
    
        ///////////////////////
        //  1. Add Liquidity //
        ///////////////////////
        CLSmartLiquidityHook.AddLiquidityParams memory params = CLSmartLiquidityHook.AddLiquidityParams({
            currency0: currency0,
            currency1: currency1,
            fee: uint24(100),
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10),
            amount0Desired: 10000e6,
            amount1Desired: 10000e6,
            amount0Min: 1,  // naive
            amount1Min: 1, // naive
            to: address(this),
            deadline: block.timestamp + 180 seconds
        });
        IAllowanceTransfer(sepoliaPermit2).approve(address(sepoliaUSDC), address(sepoliaUniversalRouter), type(uint160).max, type(uint48).max);
        IAllowanceTransfer(sepoliaPermit2).approve(address(sepoliaUSDT), address(sepoliaUniversalRouter), type(uint160).max, type(uint48).max);
        IERC20(sepoliaUSDC).approve(address(hook), type(uint).max);
        IERC20(sepoliaUSDT).approve(address(hook), type(uint).max);
        vm.broadcast();
        hook.addLiquidity(params);
        
    }

    function sort(ERC20 tokenA, ERC20 tokenB)
        internal
        pure
        returns (Currency _currency0, Currency _currency1)
    {
        if (address(tokenA) < address(tokenB)) {
            (_currency0, _currency1) = (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)));
        } else {
            (_currency0, _currency1) = (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));
        }
    }
}