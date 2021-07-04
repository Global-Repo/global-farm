// SPDX-License-Identifier: Unlicensed

import '../Managers/MasterChef.sol';
import './IBEP20.sol';

pragma solidity 0.6.12;

interface IMigratorChef {
    function migrate(IBEP20 token) external returns (IBEP20);
}