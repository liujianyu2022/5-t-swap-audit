// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TSwapPoolTest is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();

        // Since the TSwapPool contract extends the ERC20 interface contract, a new token is automatically created. 
        // the name and symbol of the the new token are "LP-Token" and "LP"
        // "pool.totalSupply()", which means that get total supply of the "LP-Token"
        // "pool.balanceOf(sb)", which means that get the "LP-Token" balance for "sb". 
        pool = new TSwapPool(address(poolToken), address(weth), "LP-Token", "LP");

        // mint 200e28 tokens to liquidityProvider
        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        // mint 10e28 tokens to user
        weth.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testBalance() public {
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);

        assertEq(poolToken.balanceOf(user), 10e18);
        assertEq(weth.balanceOf(user), 10e18);
    }



    function testDeposit() public {
        vm.startPrank(liquidityProvider);

        // the tokens will be sended to "pool" after the "approve" operation.
        weth.approve(address(pool), 60e18);
        poolToken.approve(address(pool), 50e18);
        pool.deposit(60e18, 50e18, 50e18, uint64(block.timestamp));

        // Since the TSwapPool contract extends the ERC20 interface contract, a new token is automatically created. 
        assertEq(pool.balanceOf(liquidityProvider), 60e18);
        assertEq(pool.name(), "LP-Token");
        assertEq(pool.symbol(), "LP");

        // balance of liquidityProvider
        assertEq(weth.balanceOf(liquidityProvider), 140e18);        // 200e18 - 50e18 = 150e18
        assertEq(poolToken.balanceOf(liquidityProvider), 150e18);

        // balance of pool 
        assertEq(weth.balanceOf(address(pool)), 60e18);
        assertEq(poolToken.balanceOf(address(pool)), 50e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);

        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);

        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 WETH
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000
        uint256 expected = 9e18;
        uint256 initialBalance = 10e18;             // user was minted 10e18 weth at the setUp step.

        // input      -->  output       Δy = y*[Δx/(x + Δx)]
        // poolToken  -->  weth         
        // 10e18      -->  9.09e18      Δy = 100 * [10 / (100 + 10)]
        // int256 liquidityTokensToBurn, uint256 minWethToWithdraw, uint256 minPoolTokensToWithdraw, uint64 deadline
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));

        assert(weth.balanceOf(user) >= initialBalance + expected);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);

        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        // LP-Token for liquidityProvider 
        assertEq(pool.balanceOf(address(liquidityProvider)), 100e18);
        assertEq(pool.totalLiquidityTokenSupply(), 100e18);

        assertEq(weth.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);

        // pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expected = 9e18;
        poolToken.approve(address(pool), 10e18);

        // input        -->  output           Δy = y*[Δx/(x + Δx)]
        // poolToken    -->  weth
        // 10e18             9.09e18          Δy = 100 * [10 / (100 + 10)]
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);

        // pool.approve(address(pool), 100e18);     // ???

        // withdraw(uint256 liquidityTokensToBurn, uint256 minWethToWithdraw, uint256 minPoolTokensToWithdraw, uint64 deadline
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        
        assert(weth.balanceOf(liquidityProvider) + poolToken.balanceOf(liquidityProvider) > 400e18);
    }
}
