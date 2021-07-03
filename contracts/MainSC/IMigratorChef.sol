// SPDX-License-Identifier: Unlicensed

import './MasterChef.sol';

pragma solidity 0.6.12;

interface IMigratorChef {
    function migrate(IBEP20 token) external returns (IBEP20);
}