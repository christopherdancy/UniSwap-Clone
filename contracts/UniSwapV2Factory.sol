//SPDX-License-Identifier: UNLICENSED
pragma solidity = 0.8.7;

import './UniSwapV2Pair.sol';
import './interfaces/IUniswapV2Pair.sol';

/**
* @title UniSwapV2Factory
* @author Christopher Dancy
* @notice Token Pair Factory - Use to create pair / init token contracts
 */
contract UniSwapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping (address => address)) public getPair;
    address[] public allPairs;

    /// Tokens Pairs must have unique addresses
    error NonUniqueTokenPair();
    /// Tokens cannot be address 0;
    error TokenAddressIsZero();
    /// This pair has already been created
    error PairAlreadyCreated();

    event PairCreated(address indexed token0, address indexed token1, address pair, uint allPairslength);

    /**
    * @notice Only the FeeToSetter may call the method
     */
    modifier onlyFeeToSetter{
        require (msg.sender == feeToSetter, "Only FeeToSetter may call");
        _;
    }
    
    /**
    * @dev Used to set the feeTo address
    * @param _feeToSetter address to receive the optional protocol fee
     */
    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() public view returns(uint _allPairLength) {
       _allPairLength = allPairs.length;
    }

    /**
    * @notice creates a token pair contract and returns the address of the contract
    * @dev Creates contract using the new keyword and the salt object - using encoded touple of token addresses
    * @param tokenA First token address
    * @param tokenB second token address
    * @return pair - created UniswapV2Pair contract address
     */
    function createPair(address tokenA, address tokenB) external returns(address pair) {
        if (tokenA == tokenB) {
            revert NonUniqueTokenPair();
        }
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert TokenAddressIsZero();
        }
        if (getPair[token0][token1] != address(0)){
            revert PairAlreadyCreated();
        }

        // Create contract
        bytes32 saltParam = keccak256(abi.encodePacked(token0,token1));
        pair = address(new UniSwapV2Pair{salt:saltParam}());

        // todo: Init Contract
        IUniswapV2Pair(pair).initialize(token0, token1);

        // Set Pairs
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
    * @notice updates the address that receives the optional protocol fee
    * @param _feeTo the address that receives the optional protocol fee
     */
    function setFeeTo(address _feeTo) external onlyFeeToSetter {
       feeTo = _feeTo;
    }

    /**
    * @notice updates the address that can update the address that receives the fee
    * @param _feeToSetter the address that updates setFeeTo
     */
    function setFeeToSetter(address _feeToSetter) external onlyFeeToSetter {
        feeToSetter = _feeToSetter;
    }
}
