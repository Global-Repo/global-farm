// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "Math.sol";
import "SafeMath.sol";
import "../Common/SafeBEP20.sol";
import "ReentrancyGuard.sol";
import "ReentrancyGuardUpgradeable.sol";

import "IStrategy.sol";
import "IBunnyMinter.sol";
import "IBunnyChef.sol";
import "VaultController.sol";
import {PoolConstant} from "PoolConstant.sol";
import "IStrategyLegacy.sol";
import "Minter/ZapBSC.sol";


contract VaultBunnyMaximizer is VaultController, IStrategy, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    IBEP20 private constant TOKEN = IBEP20(0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51);
    IStrategyLegacy private constant POOL = IStrategyLegacy(0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D);
    address private constant TREASURY = 0x85c9162A51E03078bdCd08D4232Bab13ed414cC3;
    // Removes excess irregularities
    uint private constant DUST = 1000;

    uint private totalShares;
    mapping (address => uint) private _shares;
    mapping (address => uint) private _principal;
    mapping (address => uint) private _depositedAt;

    function initialize() external initializer {
        __VaultController_init(TOKEN);
        __ReentrancyGuard_init();
        _stakingToken.approve(POOL, uint(- 1));
        setMinter(0x7db533569958cC6876aD8252227AaFd39c39B422);
    }

    function totalSupply() external view override returns (uint) {
        return totalShares;
    }

    function balance() public view override returns (uint) {
        return POOL.balanceOf(address(this));
    }

    function balanceOf(address account) public view override returns (uint) {
        if (totalShares == 0) return 0;
        return balance().mul(sharesOf(account)).div(totalShares);
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return balanceOf(account);
    }

    function sharesOf(address account) public view override returns (uint) {
        return _shares[account];
    }

    function principalOf(address account) public view override returns (uint) {
        return _principal[account];
    }

    function earned(address account) public view override returns (uint) {
        if (balanceOf(account) >= principalOf(account) + DUST) {
            return balanceOf(account).sub(principalOf(account));
        }

        return 0;
    }

    function priceShare() external view override returns (uint) {
        if (totalShares == 0) return 1e18;
        return balance().mul(1e18).div(totalShares);
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function rewardsToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function deposit(uint _amount) public override {
        _deposit(_amount, msg.sender);

        if (isWhitelist(msg.sender) == false) {
            _principal[msg.sender] = _principal[msg.sender].add(_amount);
            _depositedAt[msg.sender] = block.timestamp;
        }
    }

    function depositAll() external override {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    function withdrawAll() external override {
        uint amount = balanceOf(msg.sender);
        uint principal = principalOf(msg.sender);
        uint depositTimestamp = _depositedAt[msg.sender];

        totalShares = totalShares.sub(_shares[msg.sender]);
        delete _shares[msg.sender];
        delete _principal[msg.sender];
        delete _depositedAt[msg.sender];

        POOL.withdraw(amount);

        uint profit = amount > principal ? amount.sub(principal) : 0;
        uint withdrawalFee = canMint() ? _minter.withdrawalFee(principal, depositTimestamp) : 0;
        uint performanceFee = canMint() ? _minter.performanceFee(profit) : 0;

        if (withdrawalFee.add(performanceFee) > DUST) {
            _minter.mintFor(address(_stakingToken), withdrawalFee, performanceFee, msg.sender, depositTimestamp);
            if (performanceFee > 0) {
                emit ProfitPaid(msg.sender, profit, performanceFee);
            }
            amount = amount.sub(withdrawalFee).sub(performanceFee);
        }

        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, withdrawalFee);
    }

    function harvest() public override onlyKeeper {
        uint bunnyHarvested = _withdrawStakingToken(0);
        _harvest(bunnyHarvested);
    }

    function withdraw(uint shares) external override onlyWhitelisted {
        uint amount = balance().mul(shares).div(totalShares);
        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);

        IStrategyLegacy(POOL).withdraw(amount);

        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, 0);
    }

    // @dev underlying only + withdrawal fee + no perf fee
    function withdrawUnderlying(uint _amount) external {
        uint amount = Math.min(_amount, _principal[msg.sender]);
        uint shares = Math.min(amount.mul(totalShares).div(balance()), _shares[msg.sender]);
        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _principal[msg.sender] = _principal[msg.sender].sub(amount);

        IStrategyLegacy(POOL).withdraw(amount);

        uint depositTimestamp = _depositedAt[msg.sender];
        uint withdrawalFee = _minter.withdrawalFee(amount, depositTimestamp);
        if (withdrawalFee > 0) {
            _stakingToken.safeTransfer(TREASURY, withdrawalFee);
            amount = amount.sub(withdrawalFee);
        }

        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, withdrawalFee);
    }

    function getReward() public override nonReentrant {
        uint amount = earned(msg.sender);
        uint shares = Math.min(amount.mul(totalShares).div(balance()), _shares[msg.sender]);
        totalShares = totalShares.sub(shares);
        _shares[msg.sender] = _shares[msg.sender].sub(shares);
        _cleanupIfDustShares();

        uint bunnyHarvested = _withdrawStakingToken(amount);
        uint depositTimestamp = _depositedAt[msg.sender];
        uint performanceFee = canMint() ? _minter.performanceFee(amount) : 0;
        if (performanceFee > DUST) {
            _minter.mintFor(address(_stakingToken), 0, performanceFee, msg.sender, depositTimestamp);
            amount = amount.sub(performanceFee);
        }

        _stakingToken.safeTransfer(msg.sender, amount);
        emit ProfitPaid(msg.sender, amount, 0);

        _harvest(bunnyHarvested);
    }

    function _cleanupIfDustShares() private {
        uint shares = _shares[msg.sender];
        if (shares > 0 && shares < DUST) {
            totalShares = totalShares.sub(shares);
            delete _shares[msg.sender];
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinter(address newMinter) public override onlyOwner {
        VaultController.setMinter(newMinter);
    }

    function setBunnyChef(IBunnyChef _chef) public override onlyOwner {
        require(address(_bunnyChef) == address(0), "VaultBunny: setBunnyChef only once");
        VaultController.setBunnyChef(IBunnyChef(_chef));
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _withdrawStakingToken(uint amount) private returns(uint bunnyHarvested) {
        uint before = _stakingToken.balanceOf(address(this));
        POOL.withdraw(amount);
        bunnyHarvested = _stakingToken.balanceOf(address(this)).sub(amount).sub(before);
    }

    function _harvest(uint bunnyAmount) private {
        if (bunnyAmount > 0) {
            emit Harvested(bunnyAmount);
            POOL.deposit(bunnyAmount);
        }
    }

    function _deposit(uint _amount, address _to) private nonReentrant notPaused {
        uint _pool = balance();
        _stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint shares = totalShares == 0 ? _amount : (_amount.mul(totalShares)).div(_pool);

        totalShares = totalShares.add(shares);
        _shares[_to] = _shares[_to].add(shares);

        IStrategyLegacy(POOL).deposit(_amount);
        emit Deposited(_to, _amount);
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}