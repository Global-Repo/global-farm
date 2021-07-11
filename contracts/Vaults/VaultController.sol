// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../Common/SafeBEP20.sol";
import "../Common/BEP20.sol";
import "../Interfaces/ITokenRouter02.sol";
import "../Factory/ITokenPair.sol";
import "IStrategy.sol";
import "IMasterChef.sol";
import "IBunnyMinterV2.sol";
import "IBunnyChef.sol";
import "PausableUpgradeable.sol";
import "WhitelistUpgradeable.sol";

abstract contract VaultController is IVaultController, PausableUpgradeable, WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;

    BEP20 private constant GLOBAL = BEP20(0x2d1c09b9252F91019C6f31584653EB0A5E39aAB4);
    address public keeper;
    IBEP20 internal _stakingToken;
    IBunnyMinterV2 internal _minter;
    IBunnyChef internal _bunnyChef;
    uint256[49] private __gap;
    event Recovered(address token, uint amount);

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), 'VaultController: caller is not the owner or keeper');
        _;
    }

    function __VaultController_init(IBEP20 token) internal initializer {
        __PausableUpgradeable_init();
        __WhitelistUpgradeable_init();

        keeper = 0x793074D9799DC3c6039F8056F1Ba884a73462051;
        _stakingToken = token;
    }

    function minter() external view override returns (address) {
        return canMint() ? address(_minter) : address(0);
    }

    function canMint() internal view returns (bool) {
        return address(_minter) != address(0) && _minter.isMinter(address(this));
    }

    function bunnyChef() external view override returns (address) {
        return address(_bunnyChef);
    }

    function stakingToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), 'VaultController: invalid keeper address');
        keeper = _keeper;
    }

    function setMinter(address newMinter) virtual public onlyOwner {
        // can zero
        _minter = IBunnyMinterV2(newMinter);
        if (newMinter != address(0)) {
            require(newMinter == GLOBAL.getOwner(), 'VaultController: not bunny minter');
            _stakingToken.safeApprove(newMinter, 0);
            _stakingToken.safeApprove(newMinter, uint(~0));
        }
    }

    function setBunnyChef(IBunnyChef newBunnyChef) virtual public onlyOwner {
        require(address(_bunnyChef) == address(0), 'VaultController: setBunnyChef only once');
        _bunnyChef = newBunnyChef;
    }

    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        require(_token != address(_stakingToken), 'VaultController: cannot recover underlying token');
        IBEP20(_token).safeTransfer(owner(), amount);

        emit Recovered(_token, amount);
    }
}