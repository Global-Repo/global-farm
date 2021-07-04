// SPDX-License-Identifier: Unlicensed

import './IFactory.sol';
import './ITokenPair.sol';
import './ITokenBEP20.sol';
import './TokenBEP20.sol';
import './SafeMath.sol';
import './Math.sol';
import './UQ112x112.sol';
import './IBEP20.sol';
import './IGlobalCallee.sol';
import './TokenPair.sol';

pragma solidity =0.5.16;



contract Factory is IFactory {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(TokenPair).creationCode));

    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'GLOBAL: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'GLOBAL: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'GLOBAL: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(TokenPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ITokenPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'GLOBAL: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'GLOBAL: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
