
// SPDX-License-Identifier: GNU General Public License v3.0
pragma solidity 0.8.20;

import { TSwapPool } from "./TSwapPool.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

contract PoolFactory {
    error PoolFactory__PoolAlreadyExists(address tokenAddress);
    error PoolFactory__PoolDoesNotExist(address tokenAddress);

    mapping(address token => address pool) private s_pools;
    mapping(address pool => address token) private s_tokens;

    address private immutable i_wethToken;                              // WETH 代币的合约地址

    event PoolCreated(address tokenAddress, address poolAddress);

    constructor(address wethToken) {
        i_wethToken = wethToken;
    }

    function createPool(address tokenAddress) external returns (address) {
        if (s_pools[tokenAddress] != address(0)) {
            revert PoolFactory__PoolAlreadyExists(tokenAddress);
        }

        string memory liquidityTokenName = string.concat("T-Swap ", IERC20(tokenAddress).name());
        string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).symbol());

        TSwapPool tPool = new TSwapPool(tokenAddress, i_wethToken, liquidityTokenName, liquidityTokenSymbol);
        
        s_pools[tokenAddress] = address(tPool);
        s_tokens[address(tPool)] = tokenAddress;
        emit PoolCreated(tokenAddress, address(tPool));
        return address(tPool);
    }

    function getPool(address tokenAddress) external view returns (address) {
        return s_pools[tokenAddress];
    }

    function getToken(address pool) external view returns (address) {
        return s_tokens[pool];
    }

    function getWethToken() external view returns (address) {
        return i_wethToken;
    }
}
