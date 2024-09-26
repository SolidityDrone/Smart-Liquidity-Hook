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


contract HookInitializer is Script, Test{
    using CLPoolParametersHelper for bytes32;
    using PoolIdLibrary for PoolKey;
    
    
    CLPoolManager poolManager;
    CLPositionManager positionManager;
    IAllowanceTransfer permit2;
    UniversalRouter universalRouter;

    address internal sepoliaDai = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;
    address internal sepoliaUSDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;
    address internal sepoliaUSDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address internal sepoliaPermit2 = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;
    address internal sepoliaVault = 0xA9B361Df352a80BA3213c656b4EfA5436EC80362;

    address internal brevisRequest = 0x841ce48F9446C8E281D3F1444cB859b4A6D0738C;
    address internal cLPoolManagerAddress = 0x6F9302eE8760c764d775B1550C65468Ec4C25Dfc;
    address internal sepoliaAavePoolAddress = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal sepoliaPositionManager = 0x969D90aC74A1a5228b66440f8C8326a8dA47A5F9;
    address internal sepoliaUniversalRouter = 0xf342FfB466018938c6251E2CC62Cf6AD8D936cf8;

    PoolKey key;
    Currency currency0;
    Currency currency1;    
    CLSmartLiquidityHook internal hook;
    ERC20 token0;
    ERC20 token1;
    function setUp() public {
        token0 = ERC20(sepoliaUSDC);
        token1 = ERC20(sepoliaUSDT);

        (currency0, currency1) = sort(token0, token1);
    }

    function run() public {
    
        vm.broadcast();
        hook = new CLSmartLiquidityHook(
            CLPoolManager(cLPoolManagerAddress), 
            sepoliaAavePoolAddress, 
            CLPositionManager(sepoliaPositionManager), 
            IAllowanceTransfer(sepoliaPermit2), 
            UniversalRouter(payable(address(sepoliaUniversalRouter))), 
            brevisRequest
        );
   
        
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: ICLPoolManager(cLPoolManagerAddress),
            fee: uint24(100), 
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });
        vm.broadcast();
        CLPoolManager(cLPoolManagerAddress).initialize(key, Constants.SQRT_RATIO_1_1, new bytes(0));

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