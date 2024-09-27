// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CLBaseHook} from "./CLBaseHook.sol";
import {IPool} from "./interfaces/AAVE/Ipool.sol";
import {LiquidityAmounts} from "pancake-v4-core/test/pool-cl/helpers/LiquidityAmounts.sol";
import {ICLPoolManager} from "pancake-v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {TickMath} from "pancake-v4-core/src/pool-cl/libraries/TickMath.sol";
import {TickBitmap} from "pancake-v4-core/src/pool-cl/libraries/TickBitmap.sol";
import {SqrtPriceMath} from "pancake-v4-core/src/pool-cl/libraries/SqrtPriceMath.sol";
import {FixedPoint96} from "pancake-v4-core/src/pool-cl/libraries/FixedPoint96.sol";
import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {IPoolManager} from "pancake-v4-core/src/interfaces/IPoolManager.sol";
import {IVault} from "pancake-v4-core/src/interfaces/IVault.sol";
import {PoolId, PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "pancake-v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "pancake-v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "pancake-v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {Hooks} from "pancake-v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "pancake-v4-core/src/libraries/SafeCast.sol";
import {FullMath} from "pancake-v4-core/src/pool-cl/libraries/FullMath.sol";
import {CLPoolManager} from "pancake-v4-core/src/pool-cl/CLPoolManager.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "pancake-v4-core/src/types/BalanceDelta.sol";
import {PositionConfig} from "pancake-v4-periphery/src/pool-cl/libraries/PositionConfig.sol";
import {Planner, Plan} from "pancake-v4-periphery/src/libraries/Planner.sol";
import {Actions} from "pancake-v4-periphery/src/libraries/Actions.sol";
import {CLPositionManager} from "pancake-v4-periphery/src/pool-cl/CLPositionManager.sol";
import {ICLPositionManager} from "pancake-v4-periphery/src/pool-cl/interfaces/ICLPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {UniversalRouter, RouterParameters} from "pancake-v4-universal-router/src/UniversalRouter.sol";
import {SmartLiquidityToken} from "./libraries/SmartLiquidityToken.sol";
import {BrevisAppZkOnly} from "./brevis/BrevisAppZkOnly.sol";
import "@openzeppelin/contracts/access/Ownable.sol";




interface AToken {
    function scaledBalanceOf(address user) external view returns (uint256);
}

contract CLSmartLiquidityHook is CLBaseHook, BrevisAppZkOnly, Ownable{
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using CLPoolParametersHelper for bytes32;
    using SafeERC20 for IERC20;
    using Planner for Plan;



    event LiquidityAdded(address indexed user, uint amount0added, uint amount1added);
    event LiquidityRemoved(address indexed user, uint amount0, uint amount1);

    /// @notice Interact with a non-initialized pool
    error PoolNotInitialized();

    error SenderMustBeHook();

    IPool public aavePool; 

    SmartLiquidityToken public liquidityToken; 

    CLPositionManager positionManager;

    IAllowanceTransfer permit2;

    UniversalRouter universalRouter;

    bytes32 vkHash;

    bytes internal constant ZERO_BYTES = bytes("");

    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @dev The minimum amount of liquidity that must be locked in the pool
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    
    bool internal senderIsHook;

    uint internal currAmountToDeposit0;
    
    uint internal currAmountToDeposit1;

    address internal currProvider;

    address internal aavePoolDataProvider;

    bool internal withdrawTriggered;
    
    bool addAtRunTime;

    uint internal totalContributions;

    uint internal contributionMemo;

    uint internal lastUpdate;

    IERC20 internal token0;

    IERC20 internal token1;

    bool internal minted;
    RewardsAccrued public rewardsAccrued;

    mapping(address => uint) public userContributionConsumption;
 
    
    struct RewardsAccrued{
        uint token0Bal;
        uint token1Bal;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        ICLPoolManager.ModifyLiquidityParams params;
    }
 
    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        bytes32 parameters;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address to;
        uint256 deadline;
    }

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        bytes32 parameters;
        uint256 liquidity;
        uint256 deadline;
    }


    constructor(
        ICLPoolManager _poolManager,
        address _aavePool, 
        CLPositionManager _positionManager, 
        IAllowanceTransfer _permit2, 
        UniversalRouter _universalRouter,
        address _requestBrevis,
        address _aavePoolDataProvider
    ) CLBaseHook(_poolManager)BrevisAppZkOnly(_requestBrevis) Ownable(msg.sender) {
        liquidityToken = new SmartLiquidityToken("LiquidityToken", "Hello hookaton");
        aavePool = IPool(_aavePool);
        positionManager = _positionManager;
        universalRouter = _universalRouter;
        permit2 = _permit2;
        aavePoolDataProvider = _aavePoolDataProvider;
    }
    
    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }

    function afterInitialize(
        address, 
        PoolKey calldata key, 
        uint160, 
        int24, 
        bytes calldata
    )
        external
        override
        returns (bytes4)
    {
        token0 =  IERC20(Currency.unwrap(key.currency0));
        token1 =  IERC20(Currency.unwrap(key.currency1));
        return this.afterInitialize.selector;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            CLBaseHook.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: false,  
                afterRemoveLiquidityReturnsDelta: false 
            })
        );
    }

    function addLiquidity(AddLiquidityParams memory params)
        public
    {
        senderIsHook = true;
        currProvider = msg.sender;
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            hooks: this,
            poolManager: poolManager,
            fee: params.fee,
            parameters: params.parameters
        });
        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        

        uint128 poolLiquidity = poolManager.getLiquidity(poolId);
        // Split the token amounts to 30% and 70%
        uint256 amount0ToAdd = (params.amount0Desired * 30) / 100;
        uint256 amount1ToAdd = (params.amount1Desired * 30) / 100;
        uint256 amount0ToDeposit = params.amount0Desired - amount0ToAdd;
        uint256 amount1ToDeposit = params.amount1Desired - amount1ToAdd;  
        // Recalculate the liquidity for 30% of the token amounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(MIN_TICK),
            TickMath.getSqrtRatioAtTick(MAX_TICK),
            amount0ToAdd,
            amount1ToAdd
        );

        // Transfer the 70% amounts from the user
        token0.transferFrom(msg.sender, address(this), params.amount0Desired);
        token1.transferFrom(msg.sender, address(this), params.amount1Desired);
        currAmountToDeposit0 = amount0ToDeposit;
        currAmountToDeposit1 = amount1ToDeposit;

        token0.approve(address(permit2), amount0ToAdd);
        token1.approve(address(permit2), amount1ToAdd);
       
        permit2.approve(address(token0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(positionManager), type(uint160).max, type(uint48).max);

        permit2.approve(address(token0), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(universalRouter), type(uint160).max, type(uint48).max);

        if (!minted){
            PositionConfig  memory config = PositionConfig({poolKey: key, tickLower: MIN_TICK, tickUpper: MAX_TICK});
            Plan memory planner = Planner.init();
            planner = planner.add(
                Actions.CL_MINT_POSITION, abi.encode(config, liquidity, amount0ToAdd, amount1ToAdd, address(this), new bytes(0))
            );
            bytes memory data = planner.finalizeModifyLiquidityWithClose(key);
            positionManager.modifyLiquidities(data, block.timestamp);
        } else {
            PositionConfig memory config = PositionConfig({poolKey: key, tickLower: MIN_TICK, tickUpper: MAX_TICK});      
            bytes[] memory actionParams = new bytes[](3);
            actionParams[0] = abi.encode(1, config, liquidity,  type(uint128).max, type(uint128).max, ZERO_BYTES);
            actionParams[1] = abi.encode(address(token0));
            actionParams[2] = abi.encode(address(token1));
            // 0x00 is for increase liquidity; 0x17 is close currency;
            positionManager.modifyLiquiditiesWithoutLock(hex'001717', actionParams);
                
        }


        liquidityToken.mint(msg.sender, liquidity);
        totalContributions += (block.timestamp - lastUpdate) * liquidityToken.totalSupply();
        lastUpdate = block.timestamp;

        emit LiquidityAdded(msg.sender, amount0ToAdd, amount1ToAdd);
    }




    function addLiquidityDuringSwap( PoolKey memory poolKey)
        public
    {   
        senderIsHook = true;
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        IERC20 token0 =  IERC20(Currency.unwrap(poolKey.currency0));
        IERC20 token1 =  IERC20(Currency.unwrap(poolKey.currency1));
        uint desiredAmount0 = token0.balanceOf(address(this)) - rewardsAccrued.token0Bal;
        uint desiredAmount1 = token1.balanceOf(address(this)) - rewardsAccrued.token1Bal;

        uint128 liquidityToAdd = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(MIN_TICK),
            TickMath.getSqrtRatioAtTick(MAX_TICK),
            desiredAmount0,
            desiredAmount1
        );

        token0.approve(address(poolManager),  desiredAmount0);
        token1.approve(address(poolManager),  desiredAmount1);

        token0.approve(address(permit2), desiredAmount0);
        token1.approve(address(permit2), desiredAmount1);
       
        permit2.approve(address(token0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(positionManager), type(uint160).max, type(uint48).max);
      
        PositionConfig memory config = PositionConfig({poolKey: poolKey, tickLower: MIN_TICK, tickUpper: MAX_TICK});
        Plan memory planner = Planner.init();
        planner = planner.add(
            Actions.CL_INCREASE_LIQUIDITY, abi.encode(1, config, liquidityToAdd,  type(uint128).max, type(uint128).max, ZERO_BYTES)
        );
        bytes memory actions = planner.finalizeModifyLiquidityWithClose(poolKey);
  
        
        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(1, config, liquidityToAdd,  type(uint128).max, type(uint128).max, ZERO_BYTES);
        actionParams[1] = abi.encode(address(token0));
        actionParams[2] = abi.encode(address(token1));
        // 0x00 is for increase liquidity; 0x17 is close currency;
        positionManager.modifyLiquiditiesWithoutLock(hex'001717', actionParams);
        
    }


    /// @dev Users can only add liquidity through this hook
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4) {
        if (!senderIsHook) revert SenderMustBeHook();
        
        senderIsHook = false;
        return this.beforeAddLiquidity.selector;
    }
  
    function afterAddLiquidity(
        address,
        PoolKey calldata poolKey, 
        ICLPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta balanceDelta,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4, BalanceDelta) {  
        if (!withdrawTriggered){   
            token0.approve(address(aavePool), currAmountToDeposit0);
            token1.approve(address(aavePool), currAmountToDeposit1);
            aavePool.deposit(Currency.unwrap(poolKey.currency0), currAmountToDeposit0, address(this), 0);
            aavePool.deposit(Currency.unwrap(poolKey.currency1), currAmountToDeposit0, address(this), 0);
        }
  
        // Return the calculated negative BalanceDelta
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }
    
 

    function removeLiquidity(RemoveLiquidityParams calldata params)
        public
        virtual
        returns (BalanceDelta delta)
    {
        senderIsHook = true;
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            hooks: this,
            poolManager: poolManager,
            fee: params.fee,
            parameters: params.parameters
        });
        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        // Get the total liquidity before removing
        uint totalLiquidity = liquidityToken.totalSupply();

        if (totalLiquidity == 0) revert PoolNotInitialized();

        // Calculate the percentage of liquidity being removed
        uint liquidityPercentage = (params.liquidity * 1e6) / totalLiquidity;

        // Apply the percentage to withdraw the equivalent amount from Aave
        (address aToken0, address aToken1) = getAaveLiquidTokens(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));

        uint currentATokenBalance0 = IERC20(aToken0).balanceOf(address(this));
        uint currentATokenBalance1 = IERC20(aToken1).balanceOf(address(this));

        uint amountToWithdraw0 = (currentATokenBalance0 * liquidityPercentage) / 1e6;
        uint amountToWithdraw1 = (currentATokenBalance1 * liquidityPercentage) / 1e6;

        // Call the Aave withdraw function
        aavePool.withdraw(address(token0), amountToWithdraw0, address(this));
        aavePool.withdraw(address(token1), amountToWithdraw1, address(this));


         (uint unscaledBal0, uint unscaledBal1) = getUnscaledAaveBalance(address(token0), address(token1));
       // Assume unscaledBal0 and unscaledBal1 are already defined and initialized

      
        uint256 bal0 = token0.balanceOf(address(this));
        uint256 bal1 = token1.balanceOf(address(this));
        uint256 claim0 = bal0 - (unscaledBal0 * 6);
        uint256 claim1 = bal1 - (unscaledBal1 * 6);
        if (claim0 > bal0) {
            claim0 = 0; 
        }
        if (claim1 > bal1) {
            claim1 = 0;
        }
        if (claim1 > 0) {
            rewardsAccrued.token0Bal += claim0;
        }
        if (claim0 > 0) {
            rewardsAccrued.token1Bal += claim1;
        }

        // Step 4: Proceed with modifying the liquidity position and burning tokens
        PositionConfig memory config = PositionConfig({poolKey: key, tickLower: MIN_TICK, tickUpper: MAX_TICK});

        // amount0Min and amount1Min is 0 as some hook takes a fee from here
        Plan memory planner = Planner.init().add(
            Actions.CL_DECREASE_LIQUIDITY, abi.encode(1, config, params.liquidity, 0, 0, new bytes(0))
        );
        bytes memory data = planner.finalizeModifyLiquidityWithClose(key);
        positionManager.modifyLiquidities(data, block.timestamp);
        uint amountToTransfer0 = token0.balanceOf(address(this)) - rewardsAccrued.token0Bal;
        uint amountToTransfer1 = token1.balanceOf(address(this)) - rewardsAccrued.token1Bal;
        token0.transfer(msg.sender, amountToTransfer0);
        token1.transfer(msg.sender, amountToTransfer1);
        totalContributions += (block.timestamp - lastUpdate) * liquidityToken.totalSupply();
        lastUpdate = block.timestamp;
        liquidityToken.burn(msg.sender, uint(params.liquidity));
    }
    
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ICLPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4) {
        if (!senderIsHook) revert SenderMustBeHook();
        
        senderIsHook = false;
        return this.beforeRemoveLiquidity.selector;
    }


    function afterSwap(
        address, 
        PoolKey calldata poolKey, 
        ICLPoolManager.SwapParams calldata, 
        BalanceDelta, 
        bytes calldata
    ) external override returns (bytes4, int128) {   
        if (withdrawTriggered) {  
            senderIsHook = true;

            // Get the current pool price and liquidity
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
            uint128 totalLiquidity = poolManager.getLiquidity(poolKey.toId());

            // Calculate the liquidity needed to maintain the 30% in the pool
            uint256 targetLiquidity = (totalLiquidity * 30) / 100;

          

            PositionConfig memory config = PositionConfig({poolKey: poolKey, tickLower: MIN_TICK, tickUpper: MAX_TICK});
            Plan memory planner = Planner.init();
            planner = planner.add(
                Actions.CL_DECREASE_LIQUIDITY, abi.encode(1, config, targetLiquidity, 0, 0, ZERO_BYTES)
            );
            bytes memory actions = planner.finalizeModifyLiquidityWithClose(poolKey);
            ICLPoolManager.ModifyLiquidityParams memory params = ICLPoolManager.ModifyLiquidityParams({
                    tickLower: TickMath.MIN_TICK,
                    tickUpper: TickMath.MAX_TICK,
                    liquidityDelta: -(targetLiquidity.toInt256()),
                    salt: 0
            });
            bytes[] memory actionParams = new bytes[](3);
            actionParams[0] = abi.encode(1, config, targetLiquidity, 0, 0, ZERO_BYTES);
            actionParams[1] = abi.encode(address(token0));
            actionParams[2] = abi.encode(address(token1));
            // 0x01 is for decrease liquidity; 0x17 is close currency;
            positionManager.modifyLiquiditiesWithoutLock(hex'011717', actionParams);

            uint balance0 = IERC20(token0).balanceOf(address(this)) - rewardsAccrued.token0Bal;
            uint balance1 = IERC20(token1).balanceOf(address(this)) - rewardsAccrued.token1Bal;
            IERC20(token0).approve(address(aavePool), balance0);    
            IERC20(token1).approve(address(aavePool), balance1);
            
            aavePool.deposit(Currency.unwrap(poolKey.currency0), balance0, address(this), 0);
            aavePool.deposit(Currency.unwrap(poolKey.currency1), balance1, address(this), 0);

            // Reset the withdraw flag after rebalancing
            delete withdrawTriggered;
            
        } 
        delete senderIsHook;
        return (this.afterSwap.selector, 0);
    }


    function beforeSwap(
        address sender, 
        PoolKey calldata poolKey, 
        ICLPoolManager.SwapParams calldata params, 
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // Get the current pool price
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        // Get the liquidity in the pool
        uint128 liquidity = poolManager.getLiquidity(poolId);

        // Estimate the new price after the swap
        uint256 newSqrtPriceX96 = estimateNewSqrtPrice(sqrtPriceX96, params.amountSpecified, liquidity, params.zeroForOne);

        // Calculate the percentage change in price (price impact)
        uint256 priceImpact = calculatePriceImpact(sqrtPriceX96, newSqrtPriceX96);

        // If the price impact exceeds 0.5% (50 basis points), withdraw liquidity from Aave
        if (priceImpact > 50) {
            withdrawLiquidityAndInject(poolKey, sender, priceImpact);
        }
 
        // Continue the swap
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function estimateNewSqrtPrice(
        uint160 sqrtPriceX96, 
        int256 amountSpecified, 
        uint128 liquidity, 
        bool zeroForOne
    ) internal pure returns (uint160) {
        // Check if there's no swap amount
        if (amountSpecified == 0) {
            return sqrtPriceX96;
        }

        uint160 newSqrtPriceX96;
        if (zeroForOne) {
            // Token0 -> Token1 swap
            if (amountSpecified > 0) {
                // Moving price down (swapping token0 for token1)
                newSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    sqrtPriceX96, liquidity, uint256(amountSpecified), true
                );
            } else {
                // Moving price up (selling token1 for token0)
                newSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    sqrtPriceX96, liquidity, uint256(-amountSpecified), true
                );
            }
        } else {
            // Token1 -> Token0 swap
            if (amountSpecified > 0) {
                // Moving price up (swapping token1 for token0)
                newSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    sqrtPriceX96, liquidity, uint256(amountSpecified), true
                );
            } else {
                // Moving price down (selling token0 for token1)
                newSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    sqrtPriceX96, liquidity, uint256(-amountSpecified), true
                );
            }
        }
        return newSqrtPriceX96;
    }

    
    function calculatePriceImpact(uint256 currentSqrtPriceX96, uint256 newSqrtPriceX96) internal pure returns (uint256) {
        // Convert sqrtPriceX96 values back to actual prices by squaring them
        uint256 currentPrice = FullMath.mulDiv(currentSqrtPriceX96, currentSqrtPriceX96, FixedPoint96.Q96);
        uint256 newPrice = FullMath.mulDiv(newSqrtPriceX96, newSqrtPriceX96, FixedPoint96.Q96);

        // Calculate the percentage change in price (price impact)
        uint256 priceDifference = newPrice > currentPrice ? newPrice - currentPrice : currentPrice - newPrice;
        uint256 priceImpact = (priceDifference * 1e4) / currentPrice; // Basis points (1e4 = 100%)
        return priceImpact;
    }

    function withdrawLiquidityAndInject(PoolKey calldata poolKey, address sender, uint256 priceImpact) internal {
        // Withdraw liquidity from Aave proportional to the price impact
        PoolId poolId = poolKey.toId();

        (address aToken0, address aToken1) = getAaveLiquidTokens(address(token0), address(token1));

        uint amount0 = aavePool.withdraw(address(token0), IERC20(aToken0).balanceOf(address(this)), address(this));
        uint amount1 = aavePool.withdraw(address(token1), IERC20(aToken1).balanceOf(address(this)), address(this));
        (uint unscaledBal0, uint unscaledBal1) = getUnscaledAaveBalance(address(token0), address(token1));
       // Assume unscaledBal0 and unscaledBal1 are already defined and initialized

        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        uint256 claim0 = bal0 - (unscaledBal0 * 6);
        uint256 claim1 = bal1 - (unscaledBal1 * 6);
        if (claim0 > bal0) {
            claim0 = 0; 
        }
        if (claim1 > bal1) {
            claim1 = 0;
        }
        if (claim1 > 0) {
            rewardsAccrued.token0Bal += claim0;
        }
        if (claim0 > 0) {
            rewardsAccrued.token1Bal += claim1;
        }
        withdrawTriggered = true;
        addLiquidityDuringSwap(poolKey);
    }


    function getAaveLiquidTokens(address token0, address token1) internal view returns (address st0, address st1){
        st0 = IPool(address(aavePool)).getReserveData(token0).aTokenAddress;
        st1 = IPool(address(aavePool)).getReserveData(token1).aTokenAddress;
    }

    function _modifyPosition(PoolKey memory key, ICLPoolManager.ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(vault.lock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }
    
    function getUnscaledAaveBalance(address token0, address token1) internal view returns (uint unscaledbal0, uint unscaledbal1){
        uint128 liquidityIndex0 = IPool(address(aavePool)).getReserveData(token0).liquidityIndex / 1e21;
        uint128 liquidityIndex1 = IPool(address(aavePool)).getReserveData(token1).liquidityIndex / 1e21;

        uint scaledBal0divided = AToken(IPool(address(aavePool)).getReserveData(token0).aTokenAddress).scaledBalanceOf(address(this)) / 6;
        uint scaledBal1divided = AToken(IPool(address(aavePool)).getReserveData(token1).aTokenAddress).scaledBalanceOf(address(this)) / 6;

        unscaledbal0 = (scaledBal0divided * liquidityIndex0 ) / 6;
        unscaledbal1 = (scaledBal1divided * liquidityIndex1 ) / 6;
    }

    function handleProofResult(bytes32 _vkHash, bytes calldata _appCircuitOutput) internal override {

        require(vkHash == _vkHash, "invalid vk");

        (uint contribution, address contributor) = decodeOutput(_appCircuitOutput);
        uint actualContribution = contribution - userContributionConsumption[contributor];

        uint256 contributionPercentage = 
            (actualContribution * 1000000) / totalContributions;

        uint256 contributorReward0 = 
            (rewardsAccrued.token0Bal * contributionPercentage) / 1000000;

        uint256 contributorReward1 = 
            (rewardsAccrued.token1Bal * contributionPercentage) / 1000000;

        token0.transfer(contributor, contributorReward0);
        token1.transfer(contributor, contributorReward1);
        totalContributions -= contribution;
    }

    // In app circuit we have:
    // api.OutputUint(248, vol)
    function decodeOutput(bytes calldata o) internal pure returns (uint256, address) {
        uint248 contribution = uint248(bytes31(o[0:31])); 
        address contributor = address(bytes20(o[32:51]));
        return (uint256(contribution), contributor);
    }



}
