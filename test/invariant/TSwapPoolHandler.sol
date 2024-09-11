// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TSwapPoolHandler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    // Our Ghost variables
    int256 public actualDeltaY;
    int256 public expectedDeltaY;

    int256 public actualDeltaX;
    int256 public expectedDeltaX;

    int256 public startingX;
    int256 public startingY;

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(address(pool.getWeth()));
        poolToken = ERC20Mock(address(pool.getPoolToken()));
    }

    // poolToken  -->  weth    poolToken is pulled from caller, and weth is sended to caller.  
    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWethAmount) public {
        if (weth.balanceOf(address(pool)) <= pool.getMinimumWethDepositAmount()) {
            return;
        }

        outputWethAmount = bound(outputWethAmount, pool.getMinimumWethDepositAmount(), weth.balanceOf(address(pool)));
        
        // If these two values are the same, we will divide by 0
        if (outputWethAmount == weth.balanceOf(address(pool))) {
            return;
        }

        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWethAmount,                                           // outputAmount
            poolToken.balanceOf(address(pool)),                         // inputReserves
            weth.balanceOf(address(pool))                               // outputReserves
        );

        if (poolTokenAmount > type(uint64).max) {
            return;
        }

        // We * -1 since we are removing WETH from the system
        _updateStartingDeltas(int256(outputWethAmount) * -1, int256(poolTokenAmount));

        // Mint any necessary amount of pool tokens
        if (poolToken.balanceOf(user) < poolTokenAmount) {
            poolToken.mint(user, poolTokenAmount - poolToken.balanceOf(user) + 1);
        }

        vm.startPrank(user);
        
        // Approve tokens so they can be pulled by the pool during the swap
        poolToken.approve(address(pool), type(uint256).max);

        // Execute swap, giving pool tokens, receiving WETH
        pool.swapExactOutput({
            inputToken: poolToken,
            outputToken: weth,
            outputAmount: outputWethAmount,
            deadline: uint64(block.timestamp)
        });

        vm.stopPrank();

        // actualDeltaX = int256(endingPoolTokenBalance) - int256(startingX);
        // actualDeltaY = int256(endingWethBalance) - int256(startingY);
        _updateEndingDeltas();
    }

    function deposit(uint256 wethAmountToDeposit) public {
        // make the amount to deposit a "reasonable" number. We wouldn't expect someone to have type(uint256).max WETH!!
        wethAmountToDeposit = bound(wethAmountToDeposit, pool.getMinimumWethDepositAmount(), type(uint64).max);

        // poolToken  
        uint256 amountPoolTokensToDepositBasedOnWeth = pool.getPoolTokensToDepositBasedOnWeth(wethAmountToDeposit);

        // expectedDeltaX = poolTokenAmount
        // expectedDeltaY = wethAmount
        _updateStartingDeltas(int256(wethAmountToDeposit), int256(amountPoolTokensToDepositBasedOnWeth));

        vm.startPrank(liquidityProvider);
        poolToken.mint(liquidityProvider, amountPoolTokensToDepositBasedOnWeth);    // mint expectedDeltaX
        weth.mint(liquidityProvider, wethAmountToDeposit);                          // mint expectedDeltaY
        
        poolToken.approve(address(pool), amountPoolTokensToDepositBasedOnWeth);
        weth.approve(address(pool), wethAmountToDeposit);

        pool.deposit({
            wethToDeposit: wethAmountToDeposit,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: amountPoolTokensToDepositBasedOnWeth,
            deadline: uint64(block.timestamp)
        });

        vm.stopPrank();

        // actualDeltaX = int256(endingPoolTokenBalance) - int256(startingX);
        // actualDeltaY = int256(endingWethBalance) - int256(startingY);
        _updateEndingDeltas();
    }


    function _updateStartingDeltas(int256 wethAmount, int256 poolTokenAmount) internal {
        startingX = int256(poolToken.balanceOf(address(pool)));         // poolToken
        startingY = int256(weth.balanceOf(address(pool)));              // weth

        expectedDeltaX = poolTokenAmount;
        expectedDeltaY = wethAmount;
    }

    function _updateEndingDeltas() internal {
        uint256 endingPoolTokenBalance = poolToken.balanceOf(address(pool));
        uint256 endingWethBalance = weth.balanceOf(address(pool));

        // sell tokens == x == poolTokens
        int256 actualDeltaPoolToken = int256(endingPoolTokenBalance) - int256(startingX);
        int256 actualDeltaWeth = int256(endingWethBalance) - int256(startingY);
        
        actualDeltaX = actualDeltaPoolToken;
        actualDeltaY = actualDeltaWeth;
    }
}
