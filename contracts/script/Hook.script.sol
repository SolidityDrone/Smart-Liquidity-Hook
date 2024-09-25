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
}
