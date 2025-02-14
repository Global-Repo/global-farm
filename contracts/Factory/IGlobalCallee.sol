// SPDX-License-Identifier: Unlicensed

pragma solidity =0.5.16;

interface IGlobalCallee {
    function GlobalCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}