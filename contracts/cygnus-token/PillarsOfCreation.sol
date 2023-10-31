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

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  
    .              .            .               .      🛰️     .           .                .           .
           █████████           ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                      . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .           .
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===.*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                           .⠀
           🛰️          ███ ░███  ███ ░███                .                 .                 .⠀
        .             ░░██████  ░░██████                🛰️                             .                 .     
                       ░░░░░░    ░░░░░░      -------=========*         🛰️             .                     ⠀
           .                            .       .          .            .                        .             .⠀
        
        Pillars of Creation - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {IPillarsOfCreation} from "./interfaces/IPillarsOfCreation.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {DateTimeLib} from "./libraries/DateTimeLib.sol";

// Interfaces
import {IBonusRewarder} from "./interfaces/IBonusRewarder.sol";
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {IERC20} from "./interfaces/core/IERC20.sol";
import {ICygnusTerminal} from "./interfaces/core/ICygnusTerminal.sol";

/**
 *  @notice The only contract capable of minting the CYG token. The CYG token is divided between the DAO and lenders
 *          or borrowers of the Cygnus protocol.
 *          It is similar to a masterchef contract but the rewards are based on epochs. Each epoch the rewards get
 *          reduced by the `REDUCTION_FACTOR_PER_EPOCH` which is set at 1%. When deploying, the contract calculates
 *          the initial rewards per block based on:
 *            - the total amount of rewards
 *            - the total number of epochs
 *            - reduction factor.
 *
 *          rewardsAtEpochN = (totalRewards - accumulatedRewards) * reductionFactor / emissionsCurve(epochN)
 *
 *                        |
 *                   800k |_______.
 *                        |       |
 *                   700k |       |
 *                        |       |                Example with 1.75M totalRewards, 2% reduction and 100 epochs
 *                   600k |       |
 *                        |       |                                Epochs    |    Rewards
 *                   500M |       |                             -------------|---------------
 *                        |       |_______.                       00 - 24    |   800,037.32
 *          rewards  400k |       |       |                       25 - 49    |   482,794.30
 *                        |       |       |                       50 - 74    |   291,349.33
 *                   300k |       |       |_______.               75 - 99    |   175,819.05
 *                        |       |       |       |                          | 1,750,000.00
 *                   200k |       |       |       |_______
 *                        |       |       |       |       |
 *                   100k |       |       |       |       |
 *                        |       |       |       |       |
 *                        |_______|_______|_______|_______|__
 *                          00-24   25-49   50-74   75-99
 *                                     epochs
 *
 *          On any interaction the `advance` function is called to check if we can advance to a new epoch. The contract
 *          self-destructs once the final epoch is reached.
 *
 *  @title  PillarsOfCreation The only contract that can mint CYG into existence
 *  @author CygnusDAO
 */
contract PillarsOfCreation is IPillarsOfCreation, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Accounting precision for rewards per share
     */
    uint256 private constant ACC_PRECISION = 1e24;

    /**
     *  @notice Total pools receiving CYG rewards - This is different to the hangar18 shuttles. In Hangar18
     *          1 shuttle contains a borrowable and collateral. In this contract each hangar18 shuttle is divided
     *          into 2 shuttles to separate between lender and borrower rewards, and each shuttle has a unique
     *          `pillarsId`.
     */
    ShuttleInfo[] private allShuttles;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    mapping(uint256 => EpochInfo) public override getEpochInfo;

    /**
     *  @notice For lender rewards, then collateral is the Zero Address.
     *  @inheritdoc IPillarsOfCreation
     */
    mapping(address => mapping(address => ShuttleInfo)) public override getShuttleInfo; // borrowable -> collateral = Shuttle

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    mapping(address => mapping(address => mapping(address => UserInfo))) public override getUserInfo; // borrowable -> collateral -> user address = User Info

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    string public override name = "Cygnus: Pillars of Creation";

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    string public constant override version = "1.0.0";

    // Pillars settings //

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override SECONDS_PER_YEAR = 31536000; // Doesn't take into account leap years

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override DURATION = SECONDS_PER_YEAR * 8;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override TOTAL_EPOCHS = 208;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override BLOCKS_PER_EPOCH = DURATION / TOTAL_EPOCHS;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override REDUCTION_FACTOR_PER_EPOCH = 0.01e18; // 1% `cygPerblock` reduction per epoch

    // Immutables //

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    IHangar18 public immutable override hangar18;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    address public immutable override cygToken;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public immutable override totalCygRewards;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public immutable override totalCygDAO;

    // Current settings

    /**
     *  @notice Can only be set once via the `initializePillars` function
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override birth;

    /**
     *  @notice Can only be set once via the `initializePillars` function
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override death;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override cygPerBlockRewards; // Rewards for Borrowers & Lenders

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override cygPerBlockDAO; // Rewards for DAO

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override totalAllocPoint;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override lastDripDAO;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override lastEpochTime;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    address public override artificer;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    bool public override doomswitch;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Constructor that initializes the contract with the given `_hangar18`, `_rewardToken`, and `_cygPerBlock` values.
     *
     *  @param _hangar18 The address of the Hangar18 contract.
     *  @param _rewardToken The address of the reward token contract.
     *  @param _totalCygRewardsBorrows The amount of CYG tokens to be distributed to borrowers and lenders
     *  @param _totalCygRewardsDAO The amount of CYG tokens to be distributed to the DAO
     */
    constructor(IHangar18 _hangar18, address _rewardToken, uint256 _totalCygRewardsBorrows, uint256 _totalCygRewardsDAO) {
        // Total CYG to be distributed as rewards to lenders/borrowers
        totalCygRewards = _totalCygRewardsBorrows;

        // Total CYG to go to the DAO
        totalCygDAO = _totalCygRewardsDAO;

        // Set CYG token
        cygToken = _rewardToken;

        // Set factory
        hangar18 = _hangar18;
    }

    /**
     *  @dev This function is called for plain Ether transfers
     */
    receive() external payable {}

    /**
     *  @dev Fallback function is executed if none of the other functions match the function identifier or no data was provided with the function call.
     */
    fallback() external payable {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Controls important parameters in both Collateral and Borrow contracts 👽
     */
    modifier cygnusAdmin() {
        _checkAdmin();
        _;
    }

    /**
     *  @custom:modifier advance Advances the epoch if necessary and self-destructs contract if all epochs are finished
     */
    modifier advance() {
        // Try and advance epoch
        _advanceEpoch();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Internal check for msg.sender admin, checks factory's current admin 👽
     */
    function _checkAdmin() private view {
        // Current admin from the factory
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) revert PillarsOfCreation__MsgSenderNotAdmin();
    }

    /**
     *  @notice Reverts if msg.sender is not artificer
     */
    function _checkArtificer() private view {
        // Check if artificer is enabled
        if (artificerEnabled()) {
            /// @custom:error OnlyArtificer Avoid if caller is not the artificer
            if (msg.sender != artificer) revert PillarsOfCreation__OnlyArtificer();
        }
        // Artificer not enabled, check caller is admin
        else _checkAdmin();
    }

    /**
     *  @dev The pillars consists of rewards for both borrowers and lenders in each shuttle. To separate between
     *       each rewards and alloc points we set different collaterals for each, but the same borrowable.
     *       If we are setting borrow rewards then we use the actual collateral of the borrowable, if we are setting
     *       lender rewards we set the collateral as the zero address.
     */
    function _isBorrowRewards(address borrowable, bool borrowRewards) private view returns (address collateral) {
        // Check if we are adding lender or borrower rewards
        collateral = borrowRewards ? ICygnusTerminal(borrowable).collateral() : address(0);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function shuttlesLength() public view override returns (uint256) {
        return allShuttles.length;
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function getBlockTimestamp() public view override returns (uint256) {
        // Return this block's timestamp
        return block.timestamp;
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function getCurrentEpoch() public view override returns (uint256 currentEpoch) {
        // Get the current timestamp
        uint256 currentTime = getBlockTimestamp();

        // Contract has expired
        if (currentTime >= death) return TOTAL_EPOCHS;

        // Current epoch
        currentEpoch = (currentTime - birth) / BLOCKS_PER_EPOCH;
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function calculateEpochRewards(uint256 epoch, uint256 totalRewards) public pure override returns (uint256 rewards) {
        // Get cyg per block for the epoch
        uint256 _cygPerBlock = calculateCygPerBlock(epoch, totalRewards);

        // Return total CYG in the epoch
        return _cygPerBlock * BLOCKS_PER_EPOCH;
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function emissionsCurve(uint256 epoch) public pure override returns (uint) {
        // Create the emissions curve based on the reduction factor and epoch
        uint256 oneMinusReductionFactor = 1e18 - REDUCTION_FACTOR_PER_EPOCH;

        // Total Epochs
        uint256 totalEpochs = TOTAL_EPOCHS - epoch;

        // Start at 1
        uint256 result = 1e18;

        // Loop through total epochs left
        for (uint i = 0; i < totalEpochs; i++) {
            result = result.mulWad(oneMinusReductionFactor);
        }

        return 1e18 - result;
    }

    /**
     *  @notice Same claculation as in line 64. We calculate emissions at epoch 0 and then adjust the rewards by reduction
     *          factor for gas savings.
     *  @inheritdoc IPillarsOfCreation
     */
    function calculateCygPerBlock(uint256 epoch, uint256 totalRewards) public pure override returns (uint256 rewardRate) {
        // Calculate emissions curve at epoch 0 - This is what gives the slope of the curve at each epoch, given
        // total epochs and a reduction factor:
        // rewards_at_epoch_0 = (total_cyg_rewards * reduction_factor) / emissions_curve
        //                    = (1750000 * 0.02) / 0.867380
        //                    = 40351.38
        // From here we reduce 2% of the total rewards each epoch:
        // rewards_at_epoch_1 = 40351.38 * 0.98 = 39544.35
        // rewards_at_epoch_2 = 39544.35 * 0.98 = 38753.47, etc.
        uint256 emissionsAt0 = emissionsCurve(0);

        // Get rewards for epoch 0
        uint256 rewards = totalRewards.fullMulDiv(REDUCTION_FACTOR_PER_EPOCH, emissionsAt0);

        // Get total CYG rewards for `epoch`
        for (uint i = 0; i < epoch; i++) {
            rewards = rewards.mulWad(1e18 - REDUCTION_FACTOR_PER_EPOCH);
        }

        // Return the CYG per block rate at `epoch` given `totalRewards`
        rewardRate = rewards / BLOCKS_PER_EPOCH;
    }

    /**
     *  @notice Returns the latest pending CYG for `account` in this shuttle
     *  @param borrowable The address of the CygnusBorrow contract (CygUSD)
     *  @param collateral The address of the CygnusCollateral contract (CygLP)
     *  @param account The address of the user
     */
    function _pendingCyg(address borrowable, address collateral, address account) public view returns (uint256 pending) {
        // Load pool to memory
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable][collateral];

        // Load user to memory
        UserInfo memory user = getUserInfo[borrowable][collateral][account];

        // Load the accumulated reward per share
        uint256 accRewardPerShare = shuttle.accRewardPerShare;

        // Load total shares from the pool
        uint256 totalShares = shuttle.totalShares;

        // Current timestamp
        uint256 timestamp = getBlockTimestamp();

        // If the current block's timestamp is after the last reward time and there are shares in the pool
        if (timestamp > shuttle.lastRewardTime && totalShares != 0) {
            // Calculate the time elapsed since the last reward
            uint256 timeElapsed = timestamp - shuttle.lastRewardTime;

            // Calculate the reward for the elapsed time, using the pool's allocation point and total allocation points
            uint256 reward = (timeElapsed * cygPerBlockRewards * shuttle.allocPoint) / totalAllocPoint;

            // Add the calculated reward per share to the accumulated reward per share
            accRewardPerShare = accRewardPerShare + (reward * ACC_PRECISION) / totalShares;
        }

        // Calculate the pending reward for the user, based on their shares and the accumulated reward per share
        pending = uint256(int256((user.shares * accRewardPerShare) / ACC_PRECISION) - (user.rewardDebt));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Get the shuttle by ID (not the same as hangar18 `allShuttles`)
     */
    function getShuttleById(uint256 shuttleId) external view returns (ShuttleInfo memory lenders, ShuttleInfo memory borrowers) {
        // Get shuttle ID from hangar
        (, , address borrowable, address collateral, ) = hangar18.allShuttles(shuttleId);

        // Lender's pool is always with address zero as collateral
        lenders = getShuttleInfo[borrowable][address(0)];

        // Borrower's pool is with both
        borrowers = getShuttleInfo[borrowable][collateral];
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function pendingCygDAO() external view override returns (uint256 pending) {
        // Calculate time since last dao claim
        uint256 currentTime = block.timestamp;

        // Cyg accrued for the DAO
        return (currentTime - lastDripDAO) * cygPerBlockDAO;
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function pendingCyg(address borrowable, address account, bool borrowRewards) external view override returns (uint256 pending) {
        // Get collateral (lender rewards is the zero address, borrow rewards we get the borrowable's collateral)
        address collateral = _isBorrowRewards(borrowable, borrowRewards);

        // Pending CYG for this unique shuttle
        pending = _pendingCyg(borrowable, collateral, account);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function pendingCygSingle(address account, bool borrowRewards) external view returns (uint256 pending) {
        // Gas savings
        ShuttleInfo[] memory shuttles = allShuttles;

        // Length
        uint256 totalPools = shuttles.length;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalPools; i++) {
            // Get collateral
            address collateral = shuttles[i].collateral;

            // If collecting borrow rewards then we skip if collateral is address zero (lenders)
            if (borrowRewards && collateral == address(0)) continue;

            // If collecting lender rewards then we skip if collateral is not address zero
            if (!borrowRewards && collateral != address(0)) continue;

            // Collect rewards
            pending += _pendingCyg(shuttles[i].borrowable, collateral, account);
        }
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function pendingCygAll(address account) external view returns (uint256 pending) {
        // Gas savings
        ShuttleInfo[] memory shuttles = allShuttles;

        // Length
        uint256 totalShuttles = shuttles.length;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Get pending cyg for each shuttle
            // note that these shuttles are different from hangar18 shuttles as
            // collateral can be zero address here to represent lender pools
            pending += _pendingCyg(shuttles[i].borrowable, shuttles[i].collateral, account);
        }
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function pendingBonusReward(
        address borrowable,
        address collateral,
        address account
    ) external view override returns (address token, uint256 amount) {
        // Load pool to memory
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable][collateral];

        // Return bonus rewards if any
        return shuttle.bonusRewarder.pendingReward(borrowable, collateral, account);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function totalCygClaimed() public view override returns (uint256 claimed) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Loop through each epoch
        for (uint256 i = 0; i <= currentEpoch; i++) {
            // Get total claimed in this epoch and add it to previous
            claimed += getEpochInfo[i].totalClaimed;
        }
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function artificerEnabled() public view returns (bool) {
        return artificer != address(0);
    }

    // Simple view functions to get quickly

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function epochRewardsPacing() external view override returns (uint256) {
        // Get the progress to then divide by far how along we in epoch
        uint256 epochProgress = (getBlockTimestamp() - lastEpochTime).divWad(BLOCKS_PER_EPOCH);

        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Total rewards this epoch
        uint256 rewards = getEpochInfo[currentEpoch].totalRewards;

        // Claimed rewards this epoch
        uint256 claimed = getEpochInfo[currentEpoch].totalClaimed;

        // Get rewards claimed progress relative to epoch progress. ie. epoch progression is 50% and 50%
        // of rewards in this epoch have been claimed then we are at 100% or 1e18
        return claimed.divWad(rewards.mulWad(epochProgress));
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function currentEpochRewardsDAO() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate current epoch rewards
        return calculateEpochRewards(currentEpoch, totalCygDAO);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function currentEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate current epoch rewards
        return calculateEpochRewards(currentEpoch, totalCygRewards);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function previousEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate next epoch rewards
        return currentEpoch == 0 ? 0 : calculateEpochRewards(currentEpoch - 1, totalCygRewards);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function nextEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate next epoch rewards
        return calculateEpochRewards(currentEpoch + 1, totalCygRewards);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function blocksThisEpoch() external view override returns (uint256) {
        // Get how far along we are in this epoch in seconds
        return getBlockTimestamp() - lastEpochTime;
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function untilNextEpoch() external view override returns (uint256) {
        // Return seconds left until next epoch
        return BLOCKS_PER_EPOCH - (getBlockTimestamp() - lastEpochTime);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function untilSupernova() external view override returns (uint256) {
        // Return seconds until death
        return death - getBlockTimestamp();
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function epochProgression() external view override returns (uint256) {
        // Return how far along we are in this epoch scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - lastEpochTime).divWad(BLOCKS_PER_EPOCH);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function totalProgression() external view override returns (uint256) {
        // Return how far along we are in total scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - birth).divWad(DURATION);
    }

    // Datetime functions

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function timestampToDateTime(
        uint256 timestamp
    ) public pure returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second) {
        // Avoid repeating ourselves
        return DateTimeLib.timestampToDateTime(timestamp);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function diffDays(uint256 fromTimestamp, uint256 toTimestamp) public pure returns (uint256 result) {
        // Avoid repeating ourselves
        return DateTimeLib.diffDays(fromTimestamp, toTimestamp);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function daysUntilNextEpoch() external view override returns (uint256) {
        // Current epoch
        uint256 epoch = getCurrentEpoch();

        // If we are in the last epoch return 0
        if (epoch == TOTAL_EPOCHS - 1) return (0);

        // Return the days left for this epoch
        return diffDays(block.timestamp, getEpochInfo[epoch].end);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function daysUntilSupernova() external view override returns (uint256) {
        // Return how many days until we self-destruct
        return diffDays(block.timestamp, death);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function daysPassedThisEpoch() external view override returns (uint256) {
        // Current epoch
        uint256 epoch = getCurrentEpoch();

        // Return how many days in we are in this epoch
        return diffDays(getEpochInfo[epoch].start, block.timestamp);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function dateNextEpochStart()
        external
        view
        override
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second)
    {
        // Current epoch
        uint256 epoch = getCurrentEpoch();

        // Get epoch end
        uint256 nextEpochTimestamp = getEpochInfo[epoch].end;

        // Return the dateTime of the next epoch start
        return timestampToDateTime(nextEpochTimestamp);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function dateCurrentEpochStart()
        external
        view
        override
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second)
    {
        // Currrent epoch
        uint256 epoch = getCurrentEpoch();

        // block.timestamp of the start of this epoch
        uint256 thisEpochTimestamp = getEpochInfo[epoch].start;

        // Return the date time of this epoch start
        return timestampToDateTime(thisEpochTimestamp);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function dateLastEpochStart()
        external
        view
        override
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second)
    {
        // Current epoch
        uint256 epoch = getCurrentEpoch();

        // Account for epoch 0
        if (epoch == 0) return (0, 0, 0, 0, 0, 0);

        // Get when this epoch ends
        uint256 thisEpochTimestamp = getEpochInfo[epoch - 1].start;

        // Return the datetime the last epoch began
        return timestampToDateTime(thisEpochTimestamp);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function dateEpochStart(
        uint256 _epoch
    ) external view override returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second) {
        // Epoch start
        uint256 epochStart = getEpochInfo[_epoch].start;

        // Return datetime of past epoch start time
        return timestampToDateTime(epochStart);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function dateEpochEnd(
        uint256 _epoch
    ) external view override returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second) {
        // Epoch end
        uint256 epochEnd = getEpochInfo[_epoch].end;

        // Datetime of the end of the epoch
        return timestampToDateTime(epochEnd);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function dateSupernova()
        external
        view
        override
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second)
    {
        // Return the datetime this contract self-destructs
        return timestampToDateTime(death);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @dev Internal function that destroys the contract and transfers remaining funds to the owner.
     */
    function _supernova() private {
        // Get epoch, uses block.timestamp - keep this function separate to getCurrentEpoch for simplicity
        uint256 epoch = getCurrentEpoch();

        // Check if current epoch is less than total epochs
        if (epoch < TOTAL_EPOCHS) return;

        // Assert we are doomed, can only be set my admin and cannot be turned off
        assert(doomswitch);

        /// @custom:event Supernova
        emit Supernova(msg.sender, birth, death, epoch);

        // Hail Satan! ʕ•ᴥ•ʔ
        //
        // By now 8 years have passed and this contract would have minted exactly:
        //
        //   totalCygRewards + totalCygRewardsDAO
        //
        // Since the Pillars are the only minter of the CYG token, no more CYG can be minted into existence.
        // Hide self destruct as it will be deprecated and not all EVMs support it (ie ZKEVM).
        // selfdestruct(payable(admin));
    }

    /**
     *  @notice Try and advance the epoch based on the time that has passed since the last epoch
     *  @notice Called after most payable functions (except `trackRewards`) to try and advance epoch
     */
    function _advanceEpoch() private {
        // Get timestamp
        uint256 currentTime = getBlockTimestamp();

        // Time since last epoch
        uint256 timeSinceLastEpoch = currentTime - lastEpochTime;

        // Get epoch since last update
        uint256 epochsPassed = timeSinceLastEpoch / BLOCKS_PER_EPOCH;

        // Update if we are at new epoch
        if (epochsPassed > 0) {
            // Get this epoch
            uint256 currentEpoch = getCurrentEpoch();

            // Check that contract is not expired
            if (currentEpoch < TOTAL_EPOCHS) {
                // Store last epoch update
                lastEpochTime = currentTime;

                // The cygPerBlock up to this epoch
                uint256 oldCygPerBlock = cygPerBlockRewards;

                // Store new cygPerBlock
                cygPerBlockRewards = calculateCygPerBlock(currentEpoch, totalCygRewards);

                // Store this info once on each advance
                EpochInfo storage epoch = getEpochInfo[currentEpoch];

                // Store start time
                epoch.start = currentTime;

                // Store estimated end time
                epoch.end = currentTime + BLOCKS_PER_EPOCH;

                // Store current epoch number
                epoch.epoch = currentEpoch;

                // Store the `cygPerBlock` of this epoch
                epoch.cygPerBlock = cygPerBlockRewards;

                // Store the planned rewards for this epoch (same as `currentEpochRewards()`)
                epoch.totalRewards = cygPerBlockRewards * BLOCKS_PER_EPOCH;

                // Assurance
                epoch.totalClaimed = 0;

                // Store the new cyg per block for the dao
                cygPerBlockDAO = calculateCygPerBlock(currentEpoch, totalCygDAO);

                /// @custom:event NewEpoch
                emit NewEpoch(currentEpoch - 1, currentEpoch, oldCygPerBlock, cygPerBlockRewards);
            }
            // If we have passed 1 epoch and the current epoch is >= TOTAL EPOCHS then we self-destruct contract
            else _supernova();
        }
    }

    /**
     *  @notice Update the specified shuttle's reward variables to the current timestamp.
     *  @notice Updates the reward information for a specific borrowable asset. It retrieves the current
     *          ShuttleInfo for the asset, calculates the reward to be distributed based on the time elapsed
     *          since the last distribution and the pool's allocation point, updates the accumulated reward
     *          per share based on the reward distributed, and stores the updated ShuttleInfo for the asset.
     *  @param borrowable The address of the borrowable asset to update.
     *  @return shuttle The updated ShuttleInfo struct.
     */
    function _updateShuttle(address borrowable, address collateral) private returns (ShuttleInfo storage shuttle) {
        // Get the pool information
        shuttle = getShuttleInfo[borrowable][collateral];

        // Current timestamp
        uint256 timestamp = getBlockTimestamp();

        // Check if rewards can be distributed
        if (timestamp > shuttle.lastRewardTime) {
            // Calculate the reward to be distributed
            uint256 totalShares = shuttle.totalShares;

            if (totalShares > 0) {
                // Get the time elapsed to calculate the reward
                uint256 timeElapsed;

                // Never underflows
                unchecked {
                    // Calculate the time elapsed since the last reward distribution
                    timeElapsed = timestamp - shuttle.lastRewardTime;
                }

                // Calculate the reward to be distributed based on the time elapsed and the pool's allocation point
                uint256 reward = (timeElapsed * cygPerBlockRewards * shuttle.allocPoint) / totalAllocPoint;

                // Update the accumulated reward per share based on the reward distributed
                shuttle.accRewardPerShare += ((reward * ACC_PRECISION) / totalShares);
            }

            // Store last block tiemstamp
            shuttle.lastRewardTime = timestamp;
        }
    }

    /**
     *  @notice Updates all shuttles in the pillars. The shuttles are not the same as the `hangar18` shuttles,
     *          since 1 shuttle ID has 2 pillars ID.
     */
    function _accelerateTheUniverse() private {
        // Gas savings
        ShuttleInfo[] memory shuttles = allShuttles;

        // Length
        uint256 totalShuttles = shuttles.length;

        // Loop through each shuttle and update all pools - Doesn't emit event
        for (uint256 i = 0; i < totalShuttles; i++) _updateShuttle(shuttles[i].borrowable, shuttles[i].collateral);

        // Drip CYG to DAO reserves
        _dripCygDAO();

        /// @custom:event AccelerateTheUniverse
        emit AccelerateTheUniverse(totalShuttles, msg.sender, getCurrentEpoch());
    }

    /**
     *  @notice Collects the CYG the msg.sender has accrued and sends to `to`
     *  @param borrowable The address of the borrowable where borrows are stored
     *  @param to The address to send msg.sender's rewards to
     */
    function _collect(address borrowable, address collateral, address to) private returns (uint256 cygAmount) {
        // Update the pool to ensure the user's reward calculation is up-to-date.
        ShuttleInfo storage shuttle = _updateShuttle(borrowable, collateral);

        // Retrieve the user's info for the specified borrowable address.
        UserInfo storage user = getUserInfo[borrowable][collateral][msg.sender];

        // Avoid stack too deep
        {
            // Calculate the user's accumulated reward based on their shares and the pool's accumulated reward per share.
            int256 accumulatedReward = int256((user.shares * shuttle.accRewardPerShare) / ACC_PRECISION);

            // Calculate the pending reward for the user by subtracting their stored reward debt from their accumulated reward.
            cygAmount = uint256(accumulatedReward - user.rewardDebt);

            // If no rewards then return and don't collect
            if (cygAmount == 0) return 0;

            // Update the user's reward debt to reflect the current accumulated reward.
            user.rewardDebt = accumulatedReward;

            // Check for bonus rewards
            if (address(shuttle.bonusRewarder) != address(0)) {
                // Bonus rewarder is set, harvest
                shuttle.bonusRewarder.onReward(borrowable, collateral, msg.sender, to, cygAmount, user.shares);
            }
        }

        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Update total claimed for this epoch
        getEpochInfo[currentEpoch].totalClaimed += cygAmount;

        // Check that total claimed this epoch is not above the max we can mint for this epoch
        if (getEpochInfo[currentEpoch].totalClaimed > getEpochInfo[currentEpoch].totalRewards) revert("Exceeds Epoch Limit");

        // Mint new CYG
        IERC20(cygToken).mint(to, cygAmount);
    }

    /**
     *  @notice Drips CYG to the DAO reserves given the `cygPerBlockDAO` and time elapsed
     */
    function _dripCygDAO() private {
        // Calculate time since last dao claim
        uint256 currentTime = block.timestamp;

        // Cyg accrued for the DAO
        uint256 _pendingCygDAO = (currentTime - lastDripDAO) * cygPerBlockDAO;

        // Return if none accrued
        if (_pendingCygDAO == 0) return;

        // Store current time
        lastDripDAO = currentTime;

        // Latest DAO reserves contract
        address daoReserves = hangar18.daoReserves();

        // Mint new CYG
        IERC20(cygToken).mint(daoReserves, _pendingCygDAO);

        /// @custom:event CygnusDAODrip
        emit CygnusDAODrip(daoReserves, _pendingCygDAO);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Main entry point into the Pillars contract to track borrowers and lenders.
     *  @notice Rewards are tracked only from borrowables. For borrowers, rewards are updated after any borrow, 
     *          repay or liquidation (via the `_updateBorrow` function). For lenders, rewards are updated after 
     *          any CygUSD mint, burn or transfer (via the `_afterTokenTransfer` function).
     *  @inheritdoc IPillarsOfCreation
     */
    function trackRewards(address account, uint256 balance, address collateral) external override {
        // Don't allow the DAO to receive CYG rewards from reserves
        if (account == address(0) || account == hangar18.daoReserves()) return;

        // Interactions
        address borrowable = msg.sender;

        // Update and load to storage for gas savings
        ShuttleInfo storage shuttle = _updateShuttle(borrowable, collateral);

        // Get the user information for the borrower in the borrowable asset's pool
        UserInfo storage user = getUserInfo[borrowable][collateral][account];

        // User's latest shares
        uint256 newShares = balance;

        // Calculate the difference in shares for the borrower and update their shares
        int256 diffShares = int256(newShares) - int256(user.shares);

        // Calculate the difference in reward debt for the borrower and update their reward debt
        int256 diffRewardDebt = (diffShares * int256(shuttle.accRewardPerShare)) / int256(ACC_PRECISION);

        // Update shares
        user.shares = newShares;

        // Update reward debt
        user.rewardDebt = user.rewardDebt + diffRewardDebt;

        // Update the total shares of the pool of `borrowable` and `position`
        shuttle.totalShares = uint256(int256(shuttle.totalShares) + diffShares);

        // Check if bonus rewarder is set
        if (address(shuttle.bonusRewarder) != address(0)) {
            // Assign shares for user to receive bonus rewards
            shuttle.bonusRewarder.onReward(borrowable, collateral, account, account, 0, newShares);
        }

        /// @custom:event TrackShuttle
        emit TrackRewards(borrowable, account, balance, collateral);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function collect(
        address borrowable,
        bool borrowRewards,
        address to
    ) external override nonReentrant advance returns (uint256 cygAmount) {
        // Get collateral (lender rewards is the zero address, borrow rewards we get the borrowable's collateral)
        address collateral = _isBorrowRewards(borrowable, borrowRewards);

        // Checks to see if there is any pending CYG to be collected and sends to user
        cygAmount = _collect(borrowable, collateral, to);

        /// @custom:event Collect
        emit Collect(borrowable, collateral, to, cygAmount);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function collectAll(address to) external override nonReentrant advance returns (uint256 cygAmount) {
        // Gas savings
        ShuttleInfo[] memory shuttles = allShuttles;

        // Length
        uint256 totalPools = shuttles.length;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalPools; i++) {
            // Collect lend rewards
            cygAmount += _collect(shuttles[i].borrowable, shuttles[i].collateral, to);
        }

        /// @custom:event CollectAll
        emit CollectAll(totalPools, cygAmount);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function collectAllSingle(address to, bool borrowRewards) external nonReentrant advance returns (uint256 cygAmount) {
        // Gas savings
        ShuttleInfo[] memory shuttles = allShuttles;

        // Length
        uint256 totalPools = shuttles.length;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalPools; i++) {
            // Get collateral
            address collateral = shuttles[i].collateral;

            // If collecting borrow rewards then we skip if collateral is address zero (lenders)
            if (borrowRewards && collateral == address(0)) continue;

            // If collecting lender rewards then we skip if collateral is not address zero
            if (!borrowRewards && collateral != address(0)) continue;

            // Collect rewards
            cygAmount += _collect(shuttles[i].borrowable, collateral, to);
        }

        /// @custom:event CollectAll
        emit CollectAllSingle(totalPools, cygAmount, borrowRewards);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function updateShuttle(address borrowable, bool borrowRewards) external override nonReentrant {
        // Get collateral (lender rewards is the zero address, borrow rewards we get the borrowable's collateral)
        address collateral = _isBorrowRewards(borrowable, borrowRewards);

        // Update the borrower's pool for this borrowable
        _updateShuttle(borrowable, collateral);

        /// @custom:event UpdateShuttle
        emit UpdateShuttle(borrowable, collateral, msg.sender, block.timestamp, getCurrentEpoch());
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function accelerateTheUniverse() external override nonReentrant advance {
        // Manually updates all shuttles in the Pillars
        _accelerateTheUniverse();
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function dripCygDAO() external override nonReentrant advance {
        // Drip CYG to dao since `lastDripDAO`
        _dripCygDAO();
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function supernova() external override nonReentrant advance {
        // Manually updates all shuttles in the Pillars
        _accelerateTheUniverse();

        // Tries to self destruct the contract
        _supernova();
    }

    /*  -------------------------------------------------------------------------------------------------------  *
     *                                           ARTIFICER FUNCTIONS 🛠️                                          *
     *  -------------------------------------------------------------------------------------------------------  */

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function adjustRewards(address borrowable, uint256 allocPoint, bool borrowRewards) external override advance {
        // Check if artificer is enabled, else check admin
        _checkArtificer();

        // Get collateral (lending rewards use address(0) as collateral)
        address collateral = borrowRewards ? ICygnusTerminal(borrowable).collateral() : address(0);

        // Load rewards
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][collateral];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (!shuttle.active) revert PillarsOfCreation__ShuttleNotInitialized();

        // Old alloc
        uint256 oldAlloc = shuttle.allocPoint;

        // Update the total allocation points (lender rewards have already been set, or else we revert)
        totalAllocPoint = (totalAllocPoint - oldAlloc) + allocPoint;

        // Assign new points
        shuttle.allocPoint = allocPoint;

        // Update pool in array
        allShuttles[shuttle.pillarsId].allocPoint = allocPoint;

        /// @custom:event NewShuttleAllocPoint
        emit NewShuttleAllocPoint(borrowable, collateral, oldAlloc, allocPoint);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function setShuttleRewards(address borrowable, uint256 allocPoint, bool borrowRewards) external override advance {
        // Check if artificer is enabled, else check admin
        _checkArtificer();

        // Get collateral (lender rewards is the zero address, borrow rewards we get the borrowable's collateral)
        address collateral = _isBorrowRewards(borrowable, borrowRewards);

        // Load shuttle rewards
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][collateral];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing shuttle rewards twice
        if (shuttle.active) revert PillarsOfCreation__ShuttleAlreadyInitialized();

        // Update the total allocation points for Pillars
        totalAllocPoint = totalAllocPoint + allocPoint;

        // Enable shuttle rewards, cannot be initialized again
        shuttle.active = true;

        // Assign shuttle alloc points
        shuttle.allocPoint = allocPoint;

        // Assign core contracts
        shuttle.borrowable = borrowable;
        shuttle.collateral = collateral; // Lender shuttles use zero address as collateral

        // Lending pool ID - Shared by borrow and lending rewards
        shuttle.shuttleId = ICygnusTerminal(borrowable).shuttleId();

        // Unique reward pool ID
        shuttle.pillarsId = allShuttles.length;

        // Push to shuttles array
        allShuttles.push(shuttle);

        /// @custom:event NewShuttleRewards
        emit NewShuttleRewards(borrowable, collateral, totalAllocPoint, allocPoint);
    }

    // TODO: borrowRewards is necesary? I thought only borrowers receive?

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function setBonusRewarder(address borrowable, bool borrowRewards, IBonusRewarder bonusRewarder) external override advance {
        // Check if artificer is enabled, else check admin
        _checkArtificer();

        // Get collateral (lender rewards is the zero address, borrow rewards we get the borrowable's collateral)
        address collateral = _isBorrowRewards(borrowable, borrowRewards);

        // Load lender rewards
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][collateral];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (!shuttle.active) revert PillarsOfCreation__ShuttleNotInitialized();

        // Assign bonus shuttle rewards
        shuttle.bonusRewarder = bonusRewarder;

        /// @custom:event NewBonusRewarder
        emit NewBonusRewarder(borrowable, collateral, bonusRewarder);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function removeBonusRewarder(address borrowable, bool borrowRewards) external override advance {
        // Check if artificer is enabled, else check admin
        _checkArtificer();

        // Get collateral (lender rewards is the zero address, borrow rewards we get the borrowable's collateral)
        address collateral = _isBorrowRewards(borrowable, borrowRewards);

        // Load lender rewards
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][collateral];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (!shuttle.active) revert PillarsOfCreation__ShuttleNotInitialized();

        // Assign bonus shuttle rewards
        shuttle.bonusRewarder = IBonusRewarder(address(0));

        /// @custom:event NewBonusRewarder
        emit RemoveBonusRewarder(borrowable, collateral);
    }

    /*  -------------------------------------------------------------------------------------------------------  *
     *                                             ADMIN FUNCTIONS 👽                                            *
     *  -------------------------------------------------------------------------------------------------------  */

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function setArtificer(address _artificer) external override advance cygnusAdmin {
        // Artificer up until now
        address oldArtificer = artificer;

        // Assign new artificer contract - Capable of adjusting shuttle rewards, bonus rewards, etc.
        artificer = _artificer;

        /// @custom;event NewArtificer
        emit NewArtificer(oldArtificer, _artificer);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function setDoomswitch() external override advance cygnusAdmin {
        // Set the doom switch, cannot be turned off!
        if (doomswitch) return;

        // Set the doomswitch - Contract can self destruct now
        doomswitch = true;

        /// @custom:event DoomSwitchSet
        emit DoomSwitchSet(block.timestamp, msg.sender, doomswitch);
    }

    /**
     *  @notice This contract should never have any token balance, including CYG
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function sweepToken(address token) external override advance cygnusAdmin {
        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = token.balanceOf(address(this));

        // Transfer token to admin
        if (balance > 0) token.safeTransfer(msg.sender, balance);

        /// @custom:event SweepToken
        emit SweepToken(token, msg.sender, balance, getCurrentEpoch());
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin
     */
    function sweepNative() external override advance cygnusAdmin {
        // Get native balance
        uint256 balance = address(this).balance;

        // Get ETH out
        if (balance > 0) SafeTransferLib.safeTransferETH(msg.sender, balance);

        /// @custom:event SweepToken
        emit SweepToken(address(0), msg.sender, balance, getCurrentEpoch());
    }

    /*  -------------------------------------------------------------------------------------------------------  *
     *                                  INITIALIZE PILLARS - CAN ONLY BE INIT ONCE                               *
     *  -------------------------------------------------------------------------------------------------------  */

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function initializePillars() external override cygnusAdmin {
        /// @custom:error PillarsAlreadyInitialized Avoid initializing pillars twice
        if (birth != 0) revert PillarsOfCreation__PillarsAlreadyInitialized();

        // Calculate the cygPerBlock at epoch 0 for rewards
        cygPerBlockRewards = calculateCygPerBlock(0, totalCygRewards);

        // Calculate the cygPerBlock for the DAO
        cygPerBlockDAO = calculateCygPerBlock(0, totalCygDAO);

        // Current timestamp
        uint256 _birth = block.timestamp;

        // Timestamp of deployment
        birth = _birth;

        // Timestamp of when the contract self-destructs
        death = _birth + DURATION;

        // Start epoch
        lastEpochTime = _birth;

        // Store the last drip as deployment time
        lastDripDAO = _birth;

        // Store epoch
        getEpochInfo[0] = EpochInfo({
            epoch: 0,
            start: _birth,
            end: _birth + BLOCKS_PER_EPOCH,
            cygPerBlock: cygPerBlockRewards,
            totalRewards: cygPerBlockRewards * BLOCKS_PER_EPOCH,
            totalClaimed: 0
        });

        /// @custom;event InitializePillars
        emit InitializePillars(birth, death, cygPerBlockRewards, cygPerBlockDAO);

        /// @custom:event NewEpoch
        emit NewEpoch(0, 0, 0, cygPerBlockRewards);
    }
}
