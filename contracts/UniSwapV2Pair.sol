//SPDX-License-Identifier: UNLICENSED

pragma solidity = 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/Math.sol";
import "./interfaces/IUniswapV2Callee.sol";
import './interfaces/IUniswapV2Factory.sol';

/**
* @title UniSwapV2Pair
* @author Christopher Dancy
* @notice Token Pair Contract - Use router contract to interact
* @dev Low-level function calls
 */
contract UniSwapV2Pair is ERC20Permit{
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

    uint public constant MIN_LIQUIDITY = 10**3;

    address public factory;
    address public token0;
    address public token1;

    // Reserve amounts of token0 & token1
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimeStampLast;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast;


    /// Address 'incorrectAddress' must be 'factory' address
    error FactoryMustCallInitalize(address incorrectAddress);
    /// Swaps require an amount of a token to be pulled from liquidity
    error InsufficentOutputAmount();
    /// There is not enough liquidity to execute your trade
    error InsufficentLiquidity();
    /// You cannot send tokens to either token contract
    error InvalidTransferTo();
    /// You must send the Uniswap tokens to complete your swap
    error InsufficentInputAmount();
    /// P * Q must be >= K
    error InsufficentProductK();
    /// P & K must fit within uint112
    error Overflow();
    /// You must provide more liquidity to the pair
    error InsufficentLiquidityMinted();
    /// You must remove more liquidity to the pair
    error InsufficentLiquidityBurned();

    event Mint (address indexed sender, uint token0Amount, uint token1Amount);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap (address indexed sender, uint amountIn0, uint amountIn1, uint amountOut0, uint amountOut1);
    event Sync (uint112 _reserve0, uint112 _reserve1);

    constructor () ERC20Permit("UniSwapV2ERC20") ERC20("UniSwapV2ERC20", 'UNI'){
        factory = msg.sender;
    }

    function getReserves() public view returns(uint112 _reserve0, uint112 _reserve1, uint32 _blockTimeStampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimeStampLast = blockTimeStampLast;
    }

    /**
    @dev initialize token pair, should be called via factory contract
     */
    function initialize(address _token0, address _token1) external {
        if (msg.sender != factory) {
            revert FactoryMustCallInitalize(msg.sender);
        }

        token0 = _token0;
        token1 = _token1;
    }

    /**
    @dev Mints pool shares - 
    init Liquidity: geometric mean minus 1e15 for donation attacks
    Add to Liquidity: porportional to total shares
    @param transferTo - Address to send pool shares
    @return liquidityAmount - Total pool shares 
     */
    function mint(address transferTo) external returns (uint liquidityAmount) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidityAmount = Math.sqrt(amount0 * amount1) - MIN_LIQUIDITY;
            _mint(address(0), MIN_LIQUIDITY);
        } else {
            liquidityAmount = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1); 
        }
        if (liquidityAmount == 0){
            revert InsufficentLiquidityMinted();
        }
        
        _mint(transferTo, liquidityAmount);
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0) * uint(reserve1); // reserve0 and reserve1 are up-to-date

        emit Mint(msg.sender, amount0, amount1);
    }

    /**
    @dev Burns pool shares & Sends porportional tokens 
    @param transferTo - Address to send tokens
    @return amount0 - Total token0 sent  
    @return amount1 - Total token1 sent 
     */
    function burn(address transferTo) external returns (uint amount0, uint amount1){
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        // Send share tokens before transaction
        uint liquidityAmount = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply();
        amount0 = liquidityAmount * balance0 / _totalSupply;
        amount1 = liquidityAmount * balance1 / _totalSupply;
        if (amount0 == 0 || amount1 == 0) {
            revert InsufficentLiquidityBurned();
        }

        _burn(address(this), liquidityAmount);
        IERC20(token0).safeTransfer(transferTo, amount0);
        IERC20(token1).safeTransfer(transferTo, amount1);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0) * uint(reserve1);

        emit Burn(msg.sender, amount0, amount1, transferTo);
    }
    
    /**
    @dev Flash Swap - Sends tokens to user & checks input >= k - fee 
    @param amountOut0 - Total tokens token0
    @param amountOut1 - Total tokens token1
    @param transferTo - Address to send tokens
    @param data - Function data/params
     */
    function swap(uint amountOut0, uint amountOut1, address transferTo, bytes calldata data) external {
        if (amountOut0 == 0 && amountOut1 == 0) {
            revert InsufficentOutputAmount();
        }
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        if (amountOut0 > _reserve0 || amountOut1 > _reserve1) {
            revert InsufficentLiquidity();
        }

        // Scope variables to stop stack to deep (< 16 vars)
        // Init storage variables as memory for manipulation (gas savings)
        uint balance0;
        uint balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            if (transferTo == token0 || transferTo == token1) {
            revert InvalidTransferTo();
            }

            // SafeTransfer tokens
            if (amountOut0 > 0) {
                IERC20(_token0).safeTransfer(transferTo, amountOut0);
            }
            if (amountOut1 > 0) {
                IERC20(_token1).safeTransfer(transferTo, amountOut1);
            }

            // Call the uniswapv2call method on the to call
            if (data.length > 0){
                IUniswapV2Callee(transferTo).uniswapV2Call(msg.sender, amountOut0, amountOut1, data);
            }

            // Check user's token Inputs
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
            
        }

        uint amountIn0 = balance0 > _reserve0 - amountOut0 ? balance0 - (_reserve0 - amountOut0) : 0;
        uint amountIn1 = balance1 > _reserve1 - amountOut1 ? balance1 - (_reserve1 - amountOut1) : 0;
        if (amountIn0 == 0 && amountIn1 == 0) {
            revert InsufficentInputAmount();
        }
        
        {
            // Trading Fee adjusted balance
            // With flash swaps, Uniswap v2 introduces the possibility that xin and yin might both
            // be non-zero (when a user wants to pay the pair back using the same asset, rather than
            // swapping). To handle such cases while properly applying fees, the contract is written to
            // enforce the following invariant:
            // (1000 · x1 − 3 · xin) · (1000 · y1 − 3 · yin) >= 1000000 · x0 · y0
            uint balanceAdjusted0 = (balance0 * 1000) - (amountIn0 * 3);
            uint balanceAdjusted1 = (balance1 * 1000) - (amountIn1 * 3);
            if (balanceAdjusted0 * balanceAdjusted1 <= uint(_reserve0) * uint(_reserve1) * (1000 ** 2)) {
                revert InsufficentProductK();
            }
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        
        emit Swap(msg.sender, amountIn0, amountIn1, amountOut0, amountOut1);
    } 

    // skim() allows a user to withdraw the difference between the current balance of the
    // pair and 2112 − 1 to the caller, if that difference is greater than 0.
    function skim(address transferTo) external {
        IERC20(token0).safeTransfer(transferTo, (IERC20(token0).balanceOf(address(this)) - reserve0));
        IERC20(token1).safeTransfer(transferTo, (IERC20(token1).balanceOf(address(this)) - reserve1));
    }

    // functions as a recovery mechanism in the case that a token asynchronously
    // deflates the balance of a pair
    function sync() external {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0) * uint(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply() * (rootK - rootKLast);
                    uint denominator = (rootK * 5)  + rootKLast;
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _update(uint _balance0, uint _balance1, uint112 _reserve0, uint112 _reserve1) private {
        if (_balance0 > type(uint112).max || _balance1 > type(uint112).max) {
            revert Overflow();
        }
        uint32 blockTimeStamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimeStamp - blockTimeStampLast;
        if (timeElapsed > 0 && _reserve0 > 0 && _reserve1 > 0) {
            // todo: UQ112 library
            // P / Q provides a price of P in terms of Q 
            // Collect the price * timeElapsed for weighting price feeds
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }

        // update reserves w/ current balances
        reserve0 = uint112(_balance0);
        reserve1 = uint112(_balance1);
        blockTimeStampLast = blockTimeStamp;
        
        emit Sync(reserve0, reserve1);
    }
}