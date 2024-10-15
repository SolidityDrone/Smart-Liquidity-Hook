// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CLBaseHook} from "./CLBaseHook.sol";
import {IPool} from "./interfaces/AAVE/IPool.sol";
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

    // Events
    event LiquidityAdded(address indexed user, uint256 liquidity, uint256 time);
    event LiquidityRemoved(address indexed user, uint256 liquidity, uint256 time);

    // Errors
    /// @notice Error thrown when interacting with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Error thrown when the sender is not a hook
    error SenderMustBeHook();

    // State Variables
    // Addresses and contracts
    IPool public aavePool; 
    SmartLiquidityToken public liquidityToken; 
    CLPositionManager positionManager;
    IAllowanceTransfer permit2;
    UniversalRouter universalRouter;
    address internal aavePoolDataProvider;

    // Liquidity parameters
    IERC20 internal token0;
    IERC20 internal token1;

    // Current deposit amounts
    uint internal currAmountToDeposit0;
    uint internal currAmountToDeposit1;

    // Provider details
    address internal currProvider;
    
    // Configuration flags
    bool internal senderIsHook;
    bool internal withdrawTriggered;
    bool internal minted;

    // Pool parameters
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Contributions tracking
    uint internal totalContributions;
    uint internal lastUpdate;
    
    // Rewards tracking
    RewardsAccrued public rewardsAccrued;

    // Other constants
    bytes32 vkHash;
    bytes internal constant ZERO_BYTES = bytes("");
    
    // User contributions
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
    

    /////////////////
    // P U B L I C //
    /////////////////


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

    /**
    * @notice Adds liquidity to the pool.
    * @param params Parameters required to add liquidity, including the desired amounts of currency.
    */
    function addLiquidity(AddLiquidityParams memory params) public {
        // Indicate that the sender is a hook
        senderIsHook = true;
        currProvider = msg.sender;

        // Create a unique key for the pool based on input parameters
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            hooks: this,
            poolManager: poolManager,
            fee: params.fee,
            parameters: params.parameters
        });

        // Get the pool ID from the key
        PoolId poolId = key.toId();

        // Retrieve the current sqrt price from the pool manager
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        
        // Ensure the pool is initialized
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        // Fetch current liquidity in the pool
        uint128 poolLiquidity = poolManager.getLiquidity(poolId);

        // Split the token amounts: 30% for addition, 70% for deposit
        uint256 amount0ToAdd = (params.amount0Desired * 30) / 100;
        uint256 amount1ToAdd = (params.amount1Desired * 30) / 100;
        uint256 amount0ToDeposit = params.amount0Desired - amount0ToAdd;
        uint256 amount1ToDeposit = params.amount1Desired - amount1ToAdd;  

        // Calculate required liquidity for the 30% of token amounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(MIN_TICK),
            TickMath.getSqrtRatioAtTick(MAX_TICK),
            amount0ToAdd,
            amount1ToAdd
        );

        // Transfer the total desired amounts from the user to the contract
        token0.transferFrom(msg.sender, address(this), params.amount0Desired);
        token1.transferFrom(msg.sender, address(this), params.amount1Desired);

        // Store amounts to deposit
        currAmountToDeposit0 = amount0ToDeposit;
        currAmountToDeposit1 = amount1ToDeposit;

        // Approve the amounts to the permit2 contract for future operations
        token0.approve(address(permit2), amount0ToAdd);
        token1.approve(address(permit2), amount1ToAdd);
        
        // Approve position manager and universal router for maximum allowance
        permit2.approve(address(token0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(positionManager), type(uint160).max, type(uint48).max);
    

        // Mint position if it hasn't been minted yet
        bytes[] memory actionParams = new bytes[](3);
        if (!minted) {
            PositionConfig memory config = PositionConfig({poolKey: key, tickLower: MIN_TICK, tickUpper: MAX_TICK});
            Plan memory planner = Planner.init();
            
            // Add mint position action to planner
            planner = planner.add(
                Actions.CL_MINT_POSITION,
                abi.encode(config, liquidity, amount0ToAdd, amount1ToAdd, address(this), new bytes(0))
            );

            // Finalize liquidity modification
            bytes memory data = planner.finalizeModifyLiquidityWithClose(key);
            positionManager.modifyLiquidities(data, block.timestamp);
        } else {
            // Prepare action parameters for liquidity modification
            PositionConfig memory config = PositionConfig({poolKey: key, tickLower: MIN_TICK, tickUpper: MAX_TICK});      
            bytes;
            actionParams[0] = abi.encode(1, config, liquidity, type(uint128).max, type(uint128).max, ZERO_BYTES);
            actionParams[1] = abi.encode(address(token0));
            actionParams[2] = abi.encode(address(token1));
            
            // Modify liquidities without locking
            // 0x00 stands for add liquidity action 
            positionManager.modifyLiquiditiesWithoutLock(hex'001717', actionParams);
        }

        // Mint liquidity tokens for the user
        liquidityToken.mint(msg.sender, liquidity);
        
        // Update total contributions based on the time since the last update
        totalContributions += (block.timestamp - lastUpdate) * liquidityToken.totalSupply();
        lastUpdate = block.timestamp;

        // Emit event indicating liquidity has been added
        emit LiquidityAdded(msg.sender, liquidity, block.timestamp);
    }



    /**
    * @notice Removes liquidity from the pool.
    * @param params Parameters required to remove liquidity, including the amount of liquidity to withdraw.
    * @return delta The balance delta resulting from the liquidity removal.
    */
    function removeLiquidity(RemoveLiquidityParams calldata params) public virtual returns (BalanceDelta delta) {
        // Indicate that the sender is a hook
        senderIsHook = true;

        // Create a unique key for the pool based on input parameters
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            hooks: this,
            poolManager: poolManager,
            fee: params.fee,
            parameters: params.parameters
        });

        // Get the pool ID from the key
        PoolId poolId = key.toId();

        // Retrieve the current sqrt price from the pool manager
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        // Ensure the pool is initialized
        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        // Get the total liquidity before removing
        uint totalLiquidity = liquidityToken.totalSupply();
        if (totalLiquidity == 0) revert PoolNotInitialized();

        // Calculate the percentage of liquidity being removed
        uint liquidityPercentage = (params.liquidity * 1e6) / totalLiquidity;

        // Get Aave liquid tokens for the currencies
        (address aToken0, address aToken1) = getAaveLiquidTokens(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));

        // Get current Aave token balances
        uint currentATokenBalance0 = IERC20(aToken0).balanceOf(address(this));
        uint currentATokenBalance1 = IERC20(aToken1).balanceOf(address(this));

        // Calculate the amounts to withdraw based on the liquidity percentage
        uint amountToWithdraw0 = (currentATokenBalance0 * liquidityPercentage) / 1e6;
        uint amountToWithdraw1 = (currentATokenBalance1 * liquidityPercentage) / 1e6;

        // Withdraw tokens from the Aave pool
        uint amount0 = aavePool.withdraw(address(token0), amountToWithdraw0, address(this));
        uint amount1 = aavePool.withdraw(address(token1), amountToWithdraw1, address(this));

        // Get unscaled Aave balances
        (uint unscaledBal0, uint unscaledBal1) = getUnscaledAaveBalance(address(token0), address(token1));

        // Get current balances of tokens in the contract
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        
        // Check for excess tokens and update rewards accrued
        if (amount0 > (unscaledBal0 )) {
            uint256 claim0 = amount0 - (unscaledBal0 );
            if (claim0 > amount0) claim0 = 0;
            if (claim0 > 0) rewardsAccrued.token0Bal += claim0;
        }

        if (amount1 > (unscaledBal1 )) {
            uint256 claim1 = amount1 - (unscaledBal1);
            if (claim1 > amount1) claim1 = 0;
            if (claim1 > 0) rewardsAccrued.token1Bal += claim1;
        }

        // Prepare the position configuration for liquidity modification
        PositionConfig memory config = PositionConfig({poolKey: key, tickLower: MIN_TICK, tickUpper: MAX_TICK});
        Plan memory planner = Planner.init().add(
            Actions.CL_DECREASE_LIQUIDITY,
            abi.encode(1, config, params.liquidity, 0, 0, new bytes(0))
        );

        // Finalize liquidity modification
        bytes memory data = planner.finalizeModifyLiquidityWithClose(key);
        positionManager.modifyLiquidities(data, block.timestamp);

        // Calculate amounts to transfer back to the user
        uint amountToTransfer0 = token0.balanceOf(address(this)) ;
        uint amountToTransfer1 = token1.balanceOf(address(this)) ;

        // Transfer tokens back to the user
        token0.transfer(msg.sender, amountToTransfer0);
        token1.transfer(msg.sender, amountToTransfer1);

        // Update total contributions based on the time since the last update
        totalContributions += (block.timestamp - lastUpdate) * liquidityToken.totalSupply();
        lastUpdate = block.timestamp;

        // Burn the liquidity tokens from the user's balance
        liquidityToken.burn(msg.sender, uint(params.liquidity));

        // Emit event indicating liquidity has been removed
        emit LiquidityRemoved(msg.sender, params.liquidity, block.timestamp);
    }

    /**
    * @notice Sets the verification key hash.
    * @param _vkHash The new verification key hash.
    */
    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }



    ///////////////////
    // H  O  O  K  S //
    ///////////////////



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

    /// @dev Users can only remove liquidity through this hook
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
            
            positionManager.modifyLiquiditiesWithoutLock(hex'011717', actionParams);

            uint balance0 = IERC20(token0).balanceOf(address(this)) - rewardsAccrued.token0Bal;
            uint balance1 = IERC20(token1).balanceOf(address(this)) - rewardsAccrued.token1Bal;
            IERC20(token0).approve(address(aavePool), balance0);    
            IERC20(token1).approve(address(aavePool), balance1);
            
            aavePool.deposit(Currency.unwrap(poolKey.currency0), balance0, address(this), 0);
            aavePool.deposit(Currency.unwrap(poolKey.currency1), balance1, address(this), 0);

            
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



    //////////////////////
    // I N T E R N A L //
    /////////////////////
 
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

    /**
    * @notice Withdraws liquidity from Aave and injects it into the system based on price impact.
    * @param poolKey The unique key identifying the pool.
    * @param sender The address of the sender initiating the withdrawal.
    * @param priceImpact The expected price impact affecting the withdrawal.
    */
    function withdrawLiquidityAndInject(PoolKey calldata poolKey, address sender, uint256 priceImpact) internal {
        // Get the pool ID from the pool key
        PoolId poolId = poolKey.toId();

        // Retrieve Aave liquid tokens for the currencies
        (address aToken0, address aToken1) = getAaveLiquidTokens(address(token0), address(token1));

        // Withdraw the entire balance of aTokens from Aave
        uint amount0 = aavePool.withdraw(address(token0), IERC20(aToken0).balanceOf(address(this)), address(this));
        uint amount1 = aavePool.withdraw(address(token1), IERC20(aToken1).balanceOf(address(this)), address(this));

        // Get unscaled Aave balances
        (uint unscaledBal0, uint unscaledBal1) = getUnscaledAaveBalance(address(token0), address(token1));

        // Get the current balances of the tokens in the contract
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));

        // Check if balance of token0 exceeds the unscaled balance threshold
        if (bal0 > (unscaledBal0 * 1e6)) {
            uint256 claim0 = bal0 - (unscaledBal0 * 1e6);
            
            // Ensure claim does not exceed available balance
            if (claim0 > bal0) {
                claim0 = 0; 
            }

            // Update the accrued rewards for token0
            if (claim0 > 0) {
                rewardsAccrued.token0Bal += claim0;
            }
        } else {
            // If the balance is within limits, no claim is made
            uint256 claim0 = 0;
        }

        // Check if balance of token1 exceeds the unscaled balance threshold
        if (bal1 > (unscaledBal1 * 1e6)) {
            uint256 claim1 = bal1 - (unscaledBal1 * 1e6);
            
            // Ensure claim does not exceed available balance
            if (claim1 > bal1) {
                claim1 = 0; // Prevent underflow
            }

            // Update the accrued rewards for token1
            if (claim1 > 0) {
                rewardsAccrued.token1Bal += claim1;
            }
        } else {
            // If the balance is within limits, no claim is made
            uint256 claim1 = 0;
        }
        _addLiquidityDuringSwap(poolKey);
    }


    function _addLiquidityDuringSwap(PoolKey memory poolKey)
        internal
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

        uint scaledBal0divided = AToken(IPool(address(aavePool)).getReserveData(token0).aTokenAddress).scaledBalanceOf(address(this)) / 1e6;
        uint scaledBal1divided = AToken(IPool(address(aavePool)).getReserveData(token1).aTokenAddress).scaledBalanceOf(address(this)) / 1e6;

        unscaledbal0 = (scaledBal0divided * liquidityIndex0 ) / 1e6;
        unscaledbal1 = (scaledBal1divided * liquidityIndex1 ) / 1e6;
    }

    /**
    * @notice Handles the result of the proof by distributing rewards to the contributor.
    * @param _vkHash The verification key hash to validate the proof.
    * @param _appCircuitOutput The output data from the application circuit.
    */
    function handleProofResult(bytes32 _vkHash, bytes calldata _appCircuitOutput) internal override {
        // Ensure the provided verification key matches the stored one
        require(vkHash == _vkHash, "invalid vk");

        // Decode output data to retrieve contribution details
        (uint contribution, address contributor, uint lastLiquidity, uint lastTimestamp) = decodeOutput(_appCircuitOutput);
        uint timeTillNow = block.timestamp - lastTimestamp;

        // Calculate the actual contribution, factoring in the last liquidity and user consumption
        uint actualContribution = 
            (contribution + (timeTillNow * lastLiquidity)) - userContributionConsumption[contributor];

        // Ensure there are contributions to process
        require(totalContributions > 0, "No contributions");

        // Calculate the contributor's percentage of total contributions
        uint256 contributionPercentage = 
            (actualContribution * 1e6) / totalContributions;

        // Determine the rewards for the contributor based on their contribution percentage
        uint256 contributorReward0 = 
            (rewardsAccrued.token0Bal * contributionPercentage) / 1e6;

        uint256 contributorReward1 = 
            (rewardsAccrued.token1Bal * contributionPercentage) / 1e6;

        // Transfer the calculated rewards to the contributor
        token0.transfer(contributor, contributorReward0);
        token1.transfer(contributor, contributorReward1);

        // Deduct the contribution from the total contributions
        totalContributions -= contribution;
    }

    /**
    * @notice Decodes the output data from the application circuit.
    * @param o The output data to decode.
    * @return contribution The contribution amount.
    * @return contributor The address of the contributor.
    * @return lastLiquidity The last liquidity amount.
    * @return lastTimestamp The last timestamp of the contribution.
    */
    function decodeOutput(bytes calldata o) public pure returns (uint256, address, uint256, uint256) {
        // Decode the output bytes into respective variables
        uint256 contribution = uint248(bytes31(o[0:31])); 
        address contributor = address(bytes20(o[31:51]));
        uint256 lastLiquidity = uint248(bytes31(o[51:82]));
        uint256 lastTimestamp = uint248(bytes31(o[82:]));
        
        return (contribution, contributor, lastLiquidity, lastTimestamp);
    }

}
