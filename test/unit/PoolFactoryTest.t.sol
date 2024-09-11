// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { PoolFactory } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PoolFactoryTest is Test {
    PoolFactory factory;
    ERC20Mock mockWeth;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    function setUp() public {
        mockWeth = new ERC20Mock();
        factory = new PoolFactory(address(mockWeth));
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
    }

    function testCreatePool() public {
        address poolAddress1 = factory.createPool(address(tokenA));
        address poolAddress2 = factory.createPool(address(tokenB));

        assertEq(poolAddress1, factory.getPool(address(tokenA)));
        assertEq(address(tokenA), factory.getToken(poolAddress1));
        
        assertEq(poolAddress2, factory.getPool(address(tokenB)));
        assertEq(address(tokenB), factory.getToken(poolAddress2));
    }

    function testGetWethToken() public{
        assertEq(address(mockWeth), factory.getWethToken());
    }

    function testCantCreatePoolIfExists() public {
        factory.createPool(address(tokenA));
        
        vm.expectRevert(
            // abi.encodeWithSelector ensures that the revert error is specifically 
            // due to the PoolAlreadyExists error for the tokenA
            abi.encodeWithSelector(
                PoolFactory.PoolFactory__PoolAlreadyExists.selector, 
                address(tokenA)                                         // it's the parameter
            )
        );
        
        factory.createPool(address(tokenA));
    }

}

// if you just want to test this file,you can run the command as follow:
// forge test --match-path test/unit/PoolFactoryTest.t.sol