//SPDX-License-Identifier: UNLICENSED

pragma solidity = 0.8.7;

interface IUniswapV2Pair {
    event Mint (address indexed sender, uint token0Amount, uint token1Amount);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap (address indexed sender, uint amountIn0, uint amountIn1, uint amountOut0, uint amountOut1);
    event Sync (uint112 _reserve0, uint112 _reserve1);

    function MIN_LIQUIDITY() external pure returns(uint);

    function factory() external view returns(address);
    function token0() external view returns(address);
    function token1() external view returns(address); 

    function price0CumulativeLast() external view returns(uint);
    function price1CumulativeLast() external view returns(uint);
    function kLast() external view returns(uint);

    function getReserves() external view returns(uint112 _reserve0, uint112 _reserve1, uint32 _blockTimeStampLast);
    function initialize(address _token0, address _token1) external;
    function mint(address transferTo) external returns (uint liquidityAmount);
    function burn(address transferTo) external returns (uint amount0, uint amount1);
    function swap(uint amountOut0, uint amountOut1, address transferTo, bytes calldata data) external;
    function skim(address transferTo) external;
    function sync() external;
}