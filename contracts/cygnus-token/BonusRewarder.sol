//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  PillarsOfCreation.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity >=0.8.17;

// Dependencies``
import {IBonusRewarder} from "./interfaces/IBonusRewarder.sol";

// Interfaces/
import {IERC20} from "./interfaces/core/IERC20.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

contract BonusRewarder is IBonusRewarder {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @custom:struct UserInfo The struct of the user
     *  @custom:member shares The amount of deposited shares
     *  @custom:member rewardDebt The user's reward debt
     */
    struct UserInfo {
        uint256 shares;
        uint256 rewardDebt;
    }

    /**
     *  @custom:struct BonusShuttle
     *  @custom:member totalShares The shuttle's total shares
     *  @custom;member accRewardPerShare Reward per share
     *  @custom:member lastRewardTime The last time the reward per share was updated
     *  @custom:member allocPoint This shuttle's alloc point
     */
    struct ShuttleInfo {
        uint256 totalShares;
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
    }

    /**
     *  @notice The accounting precision
     */
    uint256 private constant ACC_PRECISION = 1e24;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Mapping of borrowable -> collateral = Bonus Shuttle
     */
    mapping(address => mapping(address => ShuttleInfo)) public getShuttleInfo;

    /**
     *  @notice Mapping of Bonus Shuttle -> user = User Info
     */
    mapping(address => mapping(address => mapping(address => UserInfo))) public getUserInfo;

    /**
     *  @inheritdoc IBonusRewarder
     */
    uint256 public rewardPerSec;

    /**
     *  @inheritdoc IBonusRewarder
     */
    uint256 public override totalAllocPoint;

    /**
     *  @inheritdoc IBonusRewarder
     */
    address public immutable override pillarsOfCreation;

    /**
     *  @inheritdoc IBonusRewarder
     */
    address public immutable override rewardToken;

    /**
     *  @inheritdoc IBonusRewarder
     */
    address public override admin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    constructor(address _rewardToken, uint256 _rewardPerSec, address _pillars) {
        // Bonus token given out by this rewarder
        rewardToken = _rewardToken;

        // Reward per second
        rewardPerSec = _rewardPerSec;

        // The pillars of creation contract
        pillarsOfCreation = _pillars;

        // Assign admin
        admin = msg.sender;

        /// @custom:event NewRewardPerSec
        emit NewRewardPerSec(_rewardPerSec);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Reverts if msg.sender is not admin
     */
    modifier cygnusAdmin() {
        /// custom:error OnlyAdmin
        if (msg.sender != admin) revert BonusRewarder__OnlyAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @inheritdoc IBonusRewarder
     */
    function getBlockTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     *  @inheritdoc IBonusRewarder
     */
    function pendingReward(
        address borrowable,
        address collateral,
        address _user
    ) external view override returns (address token, uint256 pending) {
        // Pool info
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable][collateral];

        // Get user info
        UserInfo memory user = getUserInfo[borrowable][collateral][_user];

        // Latest reward per share for this pool
        uint256 accRewardPerShare = shuttle.accRewardPerShare;

        // Total pool shares
        uint256 totalShares = shuttle.totalShares;
        if (getBlockTimestamp() > shuttle.lastRewardTime && totalShares != 0) {
            // Get time elapsed
            uint256 timeElapsed = getBlockTimestamp() - shuttle.lastRewardTime;

            // Calculate total reward in this time elapsed
            uint256 reward = (timeElapsed * rewardPerSec * shuttle.allocPoint) / totalAllocPoint;

            // Latest reward per share
            accRewardPerShare = accRewardPerShare + (reward * ACC_PRECISION) / totalShares;
        }

        // Pending amount to be claimed
        uint256 pendingBalance = (user.shares * accRewardPerShare) / ACC_PRECISION - user.rewardDebt;

        // Check max balance
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));

        // If pending is more than our current balance then rewards have most likely ended, send final balance to user
        pending = pendingBalance > balance ? balance : pendingBalance;

        // Reward token
        token = rewardToken;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Harvests pending bonus rewards
     *  @inheritdoc IBonusRewarder
     */
    function onReward(address borrowable, address collateral, address borrower, address to, uint256, uint256 newShares) external override {
        /// @custom:error OnlyPillarsOfCreation Avoid if sender is not pillars contract
        if (msg.sender != pillarsOfCreation) revert BonusRewarder__OnlyPillarsOfCreation();

        // Update pool
        ShuttleInfo memory shuttle = updateShuttle(borrowable, collateral);

        // Get user info
        UserInfo storage user = getUserInfo[borrowable][collateral][borrower];

        // Pending rewards
        uint256 pending;

        if (user.shares > 0) {
            // Pending bal
            pending = ((user.shares * shuttle.accRewardPerShare) / ACC_PRECISION) - user.rewardDebt;

            // Check max balance
            uint256 balance = IERC20(rewardToken).balanceOf(address(this));

            // If pending is more than our current balance then rewards have most likely ended, send final balance to user
            uint256 finalBalance = pending > balance ? balance : pending;

            // Transfer pending
            if (finalBalance > 0) rewardToken.safeTransfer(to, finalBalance);
        }

        // Update shuttle info
        getShuttleInfo[borrowable][collateral].totalShares = (shuttle.totalShares + newShares) - user.shares;

        // Update shares
        user.shares = newShares;

        // user reward debt
        user.rewardDebt = (newShares * shuttle.accRewardPerShare) / ACC_PRECISION;

        /// @custom:event OnReward
        emit OnReward(borrowable, collateral, borrower, newShares, pending);
    }

    /**
     *  @inheritdoc IBonusRewarder
     */
    function setRewardPerSec(uint256 _rewardPerSec) external override cygnusAdmin {
        // Update reward per sec
        rewardPerSec = _rewardPerSec;

        /// @custom:event NewRewardPerSec
        emit NewRewardPerSec(_rewardPerSec);
    }

    /**
     *  @inheritdoc IBonusRewarder
     */
    function initializeBonusRewards(address borrowable, address collateral, uint256 allocPoint) external override cygnusAdmin {
        // Initialize new shuttle rewards
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][collateral];

        // Update total alloc
        totalAllocPoint = (totalAllocPoint - shuttle.allocPoint) + allocPoint;
        shuttle.allocPoint = allocPoint;

        /// @custom:event NewBonusReward
        emit NewBonusReward(borrowable, collateral, allocPoint);
    }

    /**
     *  @notice Updates a shuttle
     *  @param borrowable Address of the borrowable contract (CygUSD)
     *  @param collateral Address of the collateral contract (CygLP)
     *  @return pool Shuttle struct
     */
    function updateShuttle(address borrowable, address collateral) public returns (ShuttleInfo memory pool) {
        // Shuttle update
        pool = getShuttleInfo[borrowable][collateral];

        // If time has elapsed then update shuttle
        if (getBlockTimestamp() > pool.lastRewardTime) {
            // Total shares
            uint256 totalShares = pool.totalShares;

            // Update
            if (totalShares > 0) {
                uint256 timeElapsed = getBlockTimestamp() - pool.lastRewardTime;
                uint256 reward = (timeElapsed * rewardPerSec * pool.allocPoint) / totalAllocPoint;
                pool.accRewardPerShare = pool.accRewardPerShare + (reward * ACC_PRECISION) / totalShares;
            }

            // Store
            pool.lastRewardTime = getBlockTimestamp();
            getShuttleInfo[borrowable][collateral] = pool;

            /// @custom:Event UpdateBonusShuttle
            emit UpdateBonusShuttle(borrowable, collateral, pool.lastRewardTime, totalShares, pool.accRewardPerShare);
        }
    }
}
