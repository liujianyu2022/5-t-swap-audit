// SPDX-License-Identifier: GNU General Public License v3.0
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TSwapPool is ERC20 {
    error TSwapPool__DeadlineHasPassed(uint64 deadline);
    
    error TSwapPool__MaxPoolTokenDepositTooHigh(
        uint256 maximumPoolTokensToDeposit,
        uint256 poolTokensToDeposit
    );

    error TSwapPool__MinLiquidityTokensToMintTooLow(
        uint256 minimumLiquidityTokensToMint,
        uint256 liquidityTokensToMint
    );

    error TSwapPool__WethDepositAmountTooLow(
        uint256 minimumWethDeposit,
        uint256 wethToDeposit
    );
    error TSwapPool__InvalidToken();
    error TSwapPool__OutputTooLow(uint256 actual, uint256 min);
    error TSwapPool__MustBeMoreThanZero();

    using SafeERC20 for IERC20;


    IERC20 private immutable i_wethToken;
    IERC20 private immutable i_poolToken;
    uint256 private constant MINIMUM_WETH_LIQUIDITY = 1_000_000_000;        // 1 gwei
    uint256 private swap_count = 0;
    uint256 private constant SWAP_COUNT_MAX = 10;

    event LiquidityAdded(
        address indexed liquidityProvider,
        uint256 wethDeposited,
        uint256 poolTokensDeposited
    );
    event LiquidityRemoved(
        address indexed liquidityProvider,
        uint256 wethWithdrawn,
        uint256 poolTokensWithdrawn
    );
    event Swap(
        address indexed swapper,
        IERC20 tokenIn,
        uint256 amountTokenIn,
        IERC20 tokenOut,
        uint256 amountTokenOut
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier revertIfDeadlinePassed(uint64 deadline) {
        if (deadline < uint64(block.timestamp)) {
            revert TSwapPool__DeadlineHasPassed(deadline);
        }
        _;
    }

    modifier revertIfZero(uint256 amount) {
        if (amount == 0) {
            revert TSwapPool__MustBeMoreThanZero();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address poolToken,
        address wethToken,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    ) ERC20(liquidityTokenName, liquidityTokenSymbol) {
        i_wethToken = IERC20(wethToken);
        i_poolToken = IERC20(poolToken);
    }

    /*//////////////////////////////////////////////////////////////
                        ADD AND REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to the pool
    /// @dev The invariant of this function is that the ratio of WETH, PoolTokens, and LiquidityTokens is the same before and after the transaction
    /// @param wethToDeposit Amount of WETH the user is going to deposit
    /// @param minimumLiquidityTokensToMint We derive the amount of liquidity tokens to mint from the amount of WETH the
    /// user is going to deposit, but set a minimum so they know approx what they will accept
    /// @param maximumPoolTokensToDeposit The maximum amount of pool tokens the user is willing to deposit, again it's
    /// derived from the amount of WETH the user is going to deposit
    /// @param deadline The deadline for the transaction to be completed by

    function deposit(uint256 wethToDeposit, uint256 minimumLiquidityTokensToMint, uint256 maximumPoolTokensToDeposit, uint64 deadline)
        external
        revertIfZero(wethToDeposit)
        revertIfDeadlinePassed(deadline)                // revise: deadline is parameter is unused.
        returns (uint256 liquidityTokensToMint)
    {
        if (wethToDeposit < MINIMUM_WETH_LIQUIDITY) {
            revert TSwapPool__WethDepositAmountTooLow(
                MINIMUM_WETH_LIQUIDITY,
                wethToDeposit
            );
        }

        // 向已有的流动性池添加流动性
        if (totalLiquidityTokenSupply() > 0) {

            // 获取合约中当前的 WETH 和池子代币的储备量。
            uint256 wethReserves = i_wethToken.balanceOf(address(this));
            uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));

            uint256 poolTokensToDeposit = getPoolTokensToDepositBasedOnWeth(wethToDeposit);

            if (maximumPoolTokensToDeposit < poolTokensToDeposit) {
                revert TSwapPool__MaxPoolTokenDepositTooHigh(
                    maximumPoolTokensToDeposit,
                    poolTokensToDeposit
                );
            }

            // We do the same thing for liquidity tokens. Similar math.
            liquidityTokensToMint = (wethToDeposit * totalLiquidityTokenSupply()) / wethReserves;
            
            if (liquidityTokensToMint < minimumLiquidityTokensToMint) {
                revert TSwapPool__MinLiquidityTokensToMintTooLow(
                    minimumLiquidityTokensToMint,
                    liquidityTokensToMint
                );
            }

            _addLiquidityMintAndTransfer(wethToDeposit, poolTokensToDeposit, liquidityTokensToMint);

        } else {
            
            // This will be the "initial" funding of the protocol. We are starting from blank here!
            // We just have them send the tokens in, and we mint liquidity tokens based on the weth

            _addLiquidityMintAndTransfer(wethToDeposit, maximumPoolTokensToDeposit, wethToDeposit);
            
            liquidityTokensToMint = wethToDeposit;
        }
    }

    /// @dev This is a sensitive function, and should only be called by addLiquidity
    /// @param wethToDeposit The amount of WETH the user is going to deposit
    /// @param poolTokensToDeposit The amount of pool tokens the user is going to deposit
    /// @param liquidityTokensToMint The amount of liquidity tokens the user is going to mint
    function _addLiquidityMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {

        // 调用 _mint 方法为用户铸造相应数量的流动性代币。这些流动性代币代表用户在流动性池中的份额
        // _mint 方法通常用于铸造新的代币，并将其分配给指定的地址

        _mint(msg.sender, liquidityTokensToMint);

        emit LiquidityAdded(msg.sender, poolTokensToDeposit, wethToDeposit);

        // Interactions
        // function safeTransferFrom(address from, address to, uint256 amount) external;
        // 将 WETH 从 msg.sender（调用者）转移到当前合约地址 address(this)

        i_wethToken.safeTransferFrom(msg.sender, address(this), wethToDeposit);
        i_poolToken.safeTransferFrom(msg.sender, address(this), poolTokensToDeposit);
    }

    /// @notice Removes liquidity from the pool
    /// @param liquidityTokensToBurn The number of liquidity tokens the user wants to burn
    /// @param minWethToWithdraw The minimum amount of WETH the user wants to withdraw
    /// @param minPoolTokensToWithdraw The minimum amount of pool tokens the user wants to withdraw
    /// @param deadline The deadline for the transaction to be completed by
    function withdraw(
        uint256 liquidityTokensToBurn,
        uint256 minWethToWithdraw,
        uint256 minPoolTokensToWithdraw,
        uint64 deadline
    )
        external
        revertIfDeadlinePassed(deadline)
        revertIfZero(liquidityTokensToBurn)
        revertIfZero(minWethToWithdraw)
        revertIfZero(minPoolTokensToWithdraw)
    {

        uint256 wethToWithdraw = (liquidityTokensToBurn * i_wethToken.balanceOf(address(this))) / totalLiquidityTokenSupply();
        
        uint256 poolTokensToWithdraw = (liquidityTokensToBurn * i_poolToken.balanceOf(address(this))) / totalLiquidityTokenSupply();

        if (wethToWithdraw < minWethToWithdraw) {
            revert TSwapPool__OutputTooLow(wethToWithdraw, minWethToWithdraw);
        }

        if (poolTokensToWithdraw < minPoolTokensToWithdraw) {
            revert TSwapPool__OutputTooLow(
                poolTokensToWithdraw,
                minPoolTokensToWithdraw
            );
        }

        _burn(msg.sender, liquidityTokensToBurn);

        emit LiquidityRemoved(msg.sender, wethToWithdraw, poolTokensToWithdraw);

        // transfer weth and poolToken to user (the caller)
        i_wethToken.safeTransfer(msg.sender, wethToWithdraw);
        i_poolToken.safeTransfer(msg.sender, poolTokensToWithdraw);
    }

    /*//////////////////////////////////////////////////////////////
                              GET PRICING
    //////////////////////////////////////////////////////////////*/

    function getOutputAmountBasedOnInput(uint256 inputAmount, uint256 inputReserves, uint256 outputReserves) 
        public 
        pure 
        revertIfZero(inputAmount) 
        revertIfZero(outputReserves)
        returns (uint256 outputAmount)
    {
        // this is the swap logic !!!

        // x*y = (x+Δx)*(y-Δy)   --->   x*y = x*y - x*Δy + y*Δx - Δx*Δy
        // y*Δx - Δx*Δy = x*Δy   --->   Δx*(y - Δy) = x*Δy                  ---> Δx = x*[Δy/(y - Δy)]      input  <--  output
        // x*Δy + Δx*Δy = y*Δx   --->   Δy*(x + Δx) = y*Δx                  ---> Δy = y*[Δx/(x + Δx)]      input  -->  output
        // x  --->  poolTokenReserves     
        // Δx --->  poolTokensToDeposit
        // y  --->  wethReserves     
        // Δy --->  wethToDeposit

        // inputAmount    --->  Δx      the token that caller send
        // inputReserve   --->  x
        // outputAmount   --->  Δy      the token that caller receive
        // outputReserve  --->  y

        uint256 inputAmountMinusFee = inputAmount * 997;                         // fee ratio: 0.3%
        uint256 numerator = outputReserves * inputAmountMinusFee;                // y * Δx
        uint256 denominator = (inputReserves * 1000) + inputAmountMinusFee;      // x + Δx

        return numerator / denominator;
    }

    function getInputAmountBasedOnOutput(uint256 outputAmount, uint256 inputReserves, uint256 outputReserves)
        public
        pure
        revertIfZero(outputAmount)
        revertIfZero(outputReserves)
        returns (uint256 inputAmount)
    {
        // this is the swap logic !!!

        // x*y = (x+Δx)*(y-Δy)   --->   x*y = x*y - x*Δy + y*Δx - Δx*Δy
        // y*Δx - Δx*Δy = x*Δy   --->   Δx*(y - Δy) = x*Δy                  ---> Δx = x*[Δy/(y - Δy)]       input  <--  output
        // x*Δy + Δx*Δy = y*Δx   --->   Δy*(x + Δx) = y*Δx                  ---> Δy = y*[Δx/(x + Δx)]       input  -->  output

        // inputAmount    --->  Δx      the token that caller send
        // inputReserve   --->  x
        // outputAmount   --->  Δy      the token that caller receive
        // outputReserve  --->  y  

        uint256 numerator = (inputReserves * outputAmount) * 10000;         // x * Δy       fee ratio:  0.3%
        uint256 denominator = (outputReserves - outputAmount) * 997;        // y - Δy

        return numerator / denominator;

        // return
        //     ((inputReserves * outputAmount) * 10000) /
        //     ((outputReserves - outputAmount) * 997);
    }

    // figures out how much output you can receive base on how much you input
    function swapExactInput(IERC20 inputToken, uint256 inputAmount, IERC20 outputToken, uint256 minOutputAmount, uint64 deadline)
        public
        revertIfZero(inputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 output)
    {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        // input  -->  output
        uint256 outputAmount = getOutputAmountBasedOnInput(inputAmount, inputReserves, outputReserves);

        if (outputAmount < minOutputAmount) {
            revert TSwapPool__OutputTooLow(outputAmount, minOutputAmount);
        }

        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    /*
     * @notice figures out how much you need to input based on how much output you want to receive.
     *
     * Example: You say "I want 10 output WETH, and my input is DAI"
     * The function will figure out how much DAI you need to input to get 10 WETH
     * And then execute the swap
     * @param inputToken ERC20 token to pull from caller
     * @param outputToken ERC20 token to send to caller
     * @param outputAmount The exact amount of tokens to send to caller
     */
    function swapExactOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 outputAmount,
        uint64 deadline
    )
        public
        revertIfZero(outputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 inputAmount)
    {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        inputAmount = getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);

        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    /**
     * @notice wrapper function to facilitate users selling pool tokens in exchange of WETH
     * @param poolTokenAmount amount of pool tokens to sell
     * @return wethAmount amount of WETH received by caller
     */
    function sellPoolTokens(uint256 poolTokenAmount) external returns (uint256 wethAmount) {
        return
            swapExactOutput(
                i_poolToken,
                i_wethToken,
                poolTokenAmount,
                uint64(block.timestamp)
            );
    }

    /**
     * @notice Swaps a given amount of input for a given amount of output tokens.
     * @dev Every 10 swaps, we give the caller an extra token as an extra incentive to keep trading on T-Swap.
     * @param inputToken ERC20 token to pull from caller
     * @param inputAmount Amount of tokens to pull from caller
     * @param outputToken ERC20 token to send to caller
     * @param outputAmount Amount of tokens to send to caller
     */
    function _swap(IERC20 inputToken, uint256 inputAmount, IERC20 outputToken, uint256 outputAmount) private {
        
        if (_isUnknown(inputToken) || _isUnknown(outputToken) || inputToken == outputToken) {
            revert TSwapPool__InvalidToken();
        }

        swap_count++;
        
        // achieve 10 swaps
        if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);        // 1e18
        }

        emit Swap(
            msg.sender,
            inputToken,
            inputAmount,
            outputToken,
            outputAmount
        );

        inputToken.safeTransferFrom(msg.sender, address(this), inputAmount);  // safeTransferFrom(from, to ,amount) 
        outputToken.safeTransfer(msg.sender, outputAmount);                   // safeTransfer(to, amount)
    }

    function _isUnknown(IERC20 token) private view returns (bool) {
        if (token != i_wethToken && token != i_poolToken) {
            return true;
        }
        return false;
    }


    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getPoolTokensToDepositBasedOnWeth(
        uint256 wethToDeposit
    ) public view returns (uint256) {
        // x / y = Δx / Δy
        
        // x / y = k
        // Δx / Δy = k
        // (x + Δx) / (y + Δy) = (k*y + k*Δy) / (y + Δy) = k

        // x   -->  poolTokenReserve
        // Δx  -->  poolTokenDeposit
        // y   -->  wethReserve
        // Δy  -->  wethDeposit

        uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));       // x
        uint256 wethReserves = i_wethToken.balanceOf(address(this));            // y

        return (poolTokenReserves * wethToDeposit) / wethReserves;              // Δx = x * (Δy / y)
    }

    /// @notice a more verbose way of getting the total supply of liquidity tokens
    function totalLiquidityTokenSupply() public view returns (uint256) {
        return totalSupply();
    }

    function getPoolToken() external view returns (address) {
        return address(i_poolToken);
    }

    function getWeth() external view returns (address) {
        return address(i_wethToken);
    }

    function getMinimumWethDepositAmount() external pure returns (uint256) {
        return MINIMUM_WETH_LIQUIDITY;
    }

    function getPriceOfOneWethInPoolTokens() external view returns (uint256) {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_wethToken.balanceOf(address(this)),
                i_poolToken.balanceOf(address(this))
            );
    }

    function getPriceOfOnePoolTokenInWeth() external view returns (uint256) {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_poolToken.balanceOf(address(this)),
                i_wethToken.balanceOf(address(this))
            );
    }
}

