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
 *          reduced by the `REDUCTION_FACTOR_PER_EPOCH` which is set at 2.5%. When deploying, the contract calculates
 *          the initial rewards per block based on:
 *            - the total amount of rewards
 *            - the total number of epochs
 *            - reduction factor.
 *
 *          cygPerBlockAtEpochN = (totalRewards - accumulatedRewards) * reductionFactor / emissionsCurve(epochN)
 *
 *                   700k |
 *                        |                        Example with 1.75M totalRewards, 2.5% reduction and 42 epochs
 *                   600k |_______.
 *                        |       |                                Epochs    |    Rewards
 *                   500M |       |                             -------------|---------------
 *                        |       |_______.                       00 - 10    |   597,864.47
 *          rewards  400k |       |       |                       11 - 20    |   461,139.90
 *                        |       |       |_______.               21 - 30    |   360,325.55
 *                   300k |       |       |       |_______.       31 - 42    |   327,670.07
 *                        |       |       |       |       |                  | 1,750,000.00
 *                   200k |       |       |       |       |
 *                        |       |       |       |       |
 *                   100k |       |       |       |       |
 *                        |       |       |       |       |
 *                        |_______|_______|_______|_______|__
 *                          00-10   11-20   21-30   31-42
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
     *  @custom:struct Epoch Information on each epoch
     *  @custom:member epoch The ID for this epoch
     *  @custom:member cygPerBlock The CYG reward rate for this epoch
     *  @custom:member totalRewards The total amount of CYG estimated to be rewarded in this epoch
     *  @custom:member totalClaimed The total amount of claimed CYG
     *  @custom:member start The unix timestamp of when this epoch started
     *  @custom:member end The unix timestamp of when it ended or is estimated to end
     */
    struct EpochInfo {
        uint256 epoch;
        uint256 cygPerBlock;
        uint256 totalRewards;
        uint256 totalClaimed;
        uint256 start;
        uint256 end;
    }

    /**
     *  @custom:struct ShuttleInfo Info of each borrowable
     *  @custom:member active Whether the pool is active or not
     *  @custom:member shuttleId The ID for this shuttle to identify in hangar18
     *  @custom:member totalShares The total number of shares held in the pool
     *  @custom:member accRewardPerShare The accumulated reward per share
     *  @custom:member lastRewardTime The timestamp of the last reward distribution
     *  @custom:member allocPoint The allocation points of the pool
     */
    struct ShuttleInfo {
        bool active;
        address borrowable;
        address collateral;
        uint256 totalShares;
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
        IBonusRewarder bonusRewarder;
        uint256 shuttleId;
    }

    /**
     *  @custom:struct UserInfo Shares and rewards paid to each user
     *  @custom:member shares The number of shares held by the user
     *  @custom:member rewardDebt The amount of reward debt the user has accrued
     */
    struct UserInfo {
        uint256 shares;
        int256 rewardDebt;
    }

    /**
     *  @notice Accounting precision for rewards per share
     */
    uint256 private constant ACC_PRECISION = 1e24;

    /**
     *  @notice Can never mint more than this per block
     */
    uint256 private constant MAX_CYG_PER_BLOCK = 0.475e18; // Only used in constructor

    /**
     *  @notice Total pools receiving CYG rewards
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
    mapping(address => mapping(address => ShuttleInfo)) public getShuttleInfo; // borrowable -> collateral -> Shuttle

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
    uint256 public constant override SECONDS_PER_YEAR = 31536000; // Doesn't take into account leap years

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override DURATION = SECONDS_PER_YEAR * 4;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override TOTAL_EPOCHS = 42;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override BLOCKS_PER_EPOCH = DURATION / TOTAL_EPOCHS;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public constant override REDUCTION_FACTOR_PER_EPOCH = 0.025e18; // 2.5% `cygPerblock` reduction per epoch

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

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    address public immutable override daoReserves;

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
    uint256 public override cygPerBlockRewards;

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    uint256 public override cygPerBlockDAO;

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
    bool public override doomSwitch;

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

        // The DAO's latest reserves address from the factory
        daoReserves = _hangar18.daoReserves();
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
     *  @custom:modifier onlyEOA Modifier that allows function call only if msg.sender == tx.origin
     */
    modifier onlyEOA() {
        _checkEOA();
        _;
    }

    /**
     *  @custom:modifier advance Advances the epoch if necessary and self-destructs contract if all epochs are finished
     */
    modifier advance() {
        // Try and addvance epoch
        advanceEpochPrivate();
        // Update all pools if we didn't self-destruct
        acceleratePrivate();
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
        if (msg.sender != admin) {
            revert PillarsOfCreation__MsgSenderNotAdmin({admin: admin, sender: msg.sender});
        }
    }

    /**
     *  @notice Reverts if msg.sender is not artificer
     */
    function _checkArtificer() private view {
        /// @custom;erro OnlyArtificer
        if (msg.sender != artificer) revert PillarsOfCreation__OnlyArtificer();
    }

    /**
     *  @notice Reverts if it is not considered an EOA
     */
    function _checkEOA() private view {
        /// @custom:error OnlyEOAAllowed Avoid if not called by an externally owned account
        // solhint-disable-next-line
        if (msg.sender != tx.origin) {
            // solhint-disable-next-line
            revert PillarsOfCreation__OnlyEOAAllowed({sender: msg.sender, origin: tx.origin});
        }
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

        // 1 minus the result
        return 1e18 - result;
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
    function calculateCygPerBlock(uint256 epoch, uint256 totalRewards) public pure override returns (uint256 rewardRate) {
        // Accumulator of previous rewards
        uint256 previousRewards;

        // keep track of rewards
        uint256 rewards;

        // Get total CYG rewards for `epoch`
        for (uint i = 0; i <= epoch; i++) {
            // Calculate rewards for the current epoch
            rewards = (totalRewards - previousRewards).fullMulDiv(REDUCTION_FACTOR_PER_EPOCH, emissionsCurve(i));

            // Accumulate CYG rewards released up to this point
            previousRewards += rewards;
        }

        // Return cygPerBlock for `epoch`
        rewardRate = rewards / BLOCKS_PER_EPOCH;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Get the shuttle by ID (not the same as hangar18 `allShuttles`)
     */
    function getShuttleById(uint256 shuttleId) external view returns (ShuttleInfo memory shuttle) {
        shuttle = allShuttles[shuttleId];
        return getShuttleInfo[shuttle.borrowable][shuttle.collateral];
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
    function pendingCyg(address borrowable, address collateral, address borrower) external view override returns (uint256 pending) {
        // Load pool to memory
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable][collateral];

        // Load user to memory
        UserInfo memory user = getUserInfo[borrowable][collateral][borrower];

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

    /**
     *  @inheritdoc IPillarsOfCreation
     */
    function pendingBonusReward(
        address borrowable,
        address collateral,
        address user
    ) external view override returns (address token, uint256 amount) {
        // Load pool to memory
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable][collateral];

        // Return bonus rewards if any
        return shuttle.bonusRewarder.pendingReward(borrowable, collateral, user);
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
     *  @notice This internal function advances the epoch based on the time that has passed since the last epoch
     *  @notice It calculates the time that has passed since the last epoch and the number of epochs that have passed
     *  @dev If at least one epoch has passed, it calculates the new epoch
     */
    function advanceEpochPrivate() private {
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
                // The cygPerBlock up to this epoch
                uint256 oldCygPerBlock = cygPerBlockRewards;

                // Store new cygPerBlock
                cygPerBlockRewards = calculateCygPerBlock(currentEpoch, totalCygRewards);

                // Store last epoch update
                lastEpochTime = currentTime;

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
            else supernovaPrivate();
        }
    }

    /**
     *  @dev Internal function that destroys the contract and transfers remaining funds to the owner.
     */
    function supernovaPrivate() private {
        // Get epoch, uses block.timestamp - keep this function separate to getCurrentEpoch for simplicity
        uint256 epoch = getCurrentEpoch();

        // Check if current epoch is less than total epochs
        if (epoch < TOTAL_EPOCHS) return;

        // Assert we are doomed, can only be set my admin (ideally in the last epoch)
        assert(doomSwitch);

        // Get the current admin from the factory
        address admin = hangar18.admin();

        /// @custom:event Supernova
        emit Supernova(msg.sender, birth, death, epoch);

        // Hail Satan ʕ•ᴥ•ʔ
        selfdestruct(payable(admin));
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
    function updateShuttlePrivate(address borrowable, address collateral) private returns (ShuttleInfo storage shuttle) {
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
     *  @notice Updates all pools
     */
    function acceleratePrivate() private {
        // Gas savings
        ShuttleInfo[] memory shuttles = allShuttles;

        // Length
        uint256 totalShuttles = shuttles.length;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Update all pools - doesn't emit event
            updateShuttlePrivate(shuttles[i].borrowable, shuttles[i].collateral);
        }

        // Drip to DAO reserves
        dripCygDAOPrivate();

        /// @custom:event AccelerateTheUniverse
        emit AccelerateTheUniverse(totalShuttles, msg.sender, getCurrentEpoch());
    }

    /**
     *  @notice Collects the CYG the msg.sender has accrued and sends to `to`
     *  @param borrowable The address of the borrowable where borrows are stored
     *  @param to The address to send msg.sender's rewards to
     */
    function collectPrivate(address borrowable, address collateral, address to) private returns (uint256 cygAmount) {
        // Update the pool to ensure the user's reward calculation is up-to-date.
        ShuttleInfo storage shuttle = updateShuttlePrivate(borrowable, collateral);

        // Retrieve the user's info for the specified borrowable address.
        UserInfo storage user = getUserInfo[borrowable][collateral][msg.sender];

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
    function dripCygDAOPrivate() private {
        // Calculate time since last dao claim
        uint256 currentTime = block.timestamp;

        // Cyg accrued for the DAO
        uint256 _pendingCygDAO = (currentTime - lastDripDAO) * cygPerBlockDAO;

        // Return if none accrued
        if (_pendingCygDAO == 0) return;

        // Store current time
        lastDripDAO = currentTime;

        // Mint new CYG
        IERC20(cygToken).mint(daoReserves, _pendingCygDAO);

        /// @custom:event CygnusDAODrip
        emit CygnusDAODrip(daoReserves, _pendingCygDAO);
    }

    /**
     *  @dev This contract tracks borrowers` USD loans and lenders` USD deposits. When a lender deposits in a
     *       borrowable contract, they receive CygUSD at the given exchange rate. When the CygUSD is minted, the
     *       `_afterTokenTransfer` hook will call this contract, if it is set, and pass the lender's account and
     *        amount of CygUSD minted. We query the current exchange rate on this contract to correctly assign the
     *        USD deposited value of the lender.
     *  @notice Get the CygUSD to USD exchange rate to adjust borrowable rewards
     */
    function cygUsdExchangeRate(address borrowable) private view returns (uint256) {
        // Current exchange rate
        uint256 er = ICygnusTerminal(borrowable).exchangeRate();

        // Exchange rate can never be 0
        return er == 0 ? 1e18 : er;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant
     */
    function collect(
        address borrowable,
        address collateral,
        address to
    ) external override nonReentrant advance returns (uint256 cygAmount) {
        // Checks to see if there is any pending CYG to be collected and sends to user
        cygAmount = collectPrivate(borrowable, collateral, to);

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
            cygAmount += collectPrivate(shuttles[i].borrowable, shuttles[i].collateral, to);
        }

        /// @custom:event CollectAll
        emit CollectAll(totalPools, cygAmount);
    }

    /**
     *  @dev No advance for gas savings since this gets called during borrows/mints. Only update the pool of the caller
     *  @inheritdoc IPillarsOfCreation
     */
    function trackRewards(address account, uint256 balance, address collateral) external override {
        // Don't allow the DAO to receive CYG rewards from positions (in case of minted CygUSD or if we have CygLP positions)
        if (account == address(0) || account == daoReserves) return;

        // Interactions
        address borrowable = msg.sender;

        // Update and load to storage for gas savings
        ShuttleInfo storage shuttle = updateShuttlePrivate(borrowable, collateral);

        // Get the user information for the borrower in the borrowable asset's pool
        UserInfo storage user = getUserInfo[borrowable][collateral][account];

        // User's latest shares
        uint256 newShares = collateral == address(0) ? balance.mulWad(cygUsdExchangeRate(borrowable)) : balance;

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
     *  @custom:security non-reentrant only-eoa
     */
    function updateShuttle(address borrowable, address collateral) external override nonReentrant onlyEOA advance {
        // Update the borrower's pool for this borrowable
        updateShuttlePrivate(borrowable, collateral);

        /// @custom:event UpdateShuttle
        emit UpdateShuttle(borrowable, msg.sender, block.timestamp, getCurrentEpoch());
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant only-eoa
     */
    function supernova() external override nonReentrant onlyEOA advance {
        // Calls the internal destroy function, anyone can call
        supernovaPrivate();
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant only-eoa
     */
    function accelerateTheUniverse() external override nonReentrant onlyEOA advance {}

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant only-eoa
     */
    function dripCygDAO() external override nonReentrant onlyEOA advance {
        dripCygDAOPrivate();
    }

    /*  ────────── Admin ────────── */

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function adjustRewards(address borrowable, address collateral, uint256 allocPoint) external override advance {
        // Check if artificer is enabled, reverts if msg.sender is not artificer
        if (artificerEnabled()) {
            _checkArtificer();
        }
        // Artificer not enabled, if caller is admin
        else _checkAdmin();

        // Load lender rewards
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][collateral];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (!shuttle.active) revert PillarsOfCreation__ShuttleNotInitialized();

        // Old alloc
        uint256 oldAlloc = shuttle.allocPoint;

        // Update the total allocation points (lender rewards have already been set, or else we revert)
        totalAllocPoint = (totalAllocPoint - oldAlloc) + allocPoint;

        // Assign new points
        shuttle.allocPoint = allocPoint;

        /// @custom:event NewShuttleAllocPoint
        emit NewShuttleAllocPoint(borrowable, collateral, oldAlloc, allocPoint);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function setLendingRewards(address borrowable, uint256 allocPoint) external override advance {
        // Check if artificer is enabled, reverts if msg.sender is not artificer
        if (artificerEnabled()) {
            _checkArtificer();
        }
        // Artificer not enabled, caller must be admin or revert
        else _checkAdmin();

        // Load lender rewards
        ShuttleInfo storage lenderRewards = getShuttleInfo[borrowable][address(0)];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (lenderRewards.active) revert PillarsOfCreation__BorrowableAlreadyInitialized();

        // Update the total allocation points (lender rewards have already been set, or else we revert)
        totalAllocPoint = (totalAllocPoint - lenderRewards.allocPoint) + allocPoint;

        // Enable
        lenderRewards.active = true;

        // Assign alloc
        lenderRewards.allocPoint = allocPoint;

        // Lender collateral is always 0
        lenderRewards.borrowable = borrowable;
        lenderRewards.collateral = address(0);

        // Lending pool ID
        lenderRewards.shuttleId = ICygnusTerminal(borrowable).shuttleId();

        // Push to shuttles array
        allShuttles.push(lenderRewards);

        /// @custom:event NewShuttleReward
        emit NewBorrowableReward(borrowable, address(0), totalAllocPoint, allocPoint);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function setBorrowRewards(address borrowable, address collateral, uint256 allocPoint) external override advance {
        // Check if artificer is enabled, reverts if msg.sender is not artificer
        if (artificerEnabled()) {
            _checkArtificer();
        }
        // Artificer not enabled, caller must be admin or revert
        else _checkAdmin();

        // Load lender rewards
        ShuttleInfo storage borrowRewards = getShuttleInfo[borrowable][collateral];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (borrowRewards.active) revert PillarsOfCreation__CollateralAlreadyInitialized();

        // Update the total allocation points (lender rewards have already been set, or else we revert)
        totalAllocPoint = (totalAllocPoint - borrowRewards.allocPoint) + allocPoint;

        // Enable
        borrowRewards.active = true;

        // Assign alloc
        borrowRewards.allocPoint = allocPoint;

        // Set pools
        borrowRewards.borrowable = borrowable;
        borrowRewards.collateral = collateral;

        // Lending pool ID
        borrowRewards.shuttleId = ICygnusTerminal(collateral).shuttleId();

        // Push to shuttles array
        allShuttles.push(borrowRewards);

        /// @custom:event NewShuttleReward
        emit NewCollateralReward(borrowable, collateral, totalAllocPoint, allocPoint);
    }

    /**
     *  @notice Bonus rewards are only for borrowers
     *  @custom:security only-admin or only-artificer
     */
    function setBonusRewarder(address borrowable, address collateral, IBonusRewarder bonusRewarder) external override advance {
        // Check if artificer is enabled, reverts if msg.sender is not artificer
        if (artificerEnabled()) {
            _checkArtificer();
        }
        // Artificer not enabled, if caller is admin
        else _checkAdmin();

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
     *  @custom:security only-admin 👽
     */
    function setDoomSwitch() external override advance cygnusAdmin {
        // Set the doom switch, cannot be turned off!
        doomSwitch = true;

        /// @custom:event DoomSwitchSet
        emit DoomSwitchSet(block.timestamp, msg.sender, doomSwitch);
    }

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security only-admin 👽
     */
    function setArtificer(address _artificer) external override advance cygnusAdmin {
        artificer = _artificer;
    }

    // This contract should never have any balances

    /**
     *  @inheritdoc IPillarsOfCreation
     *  @custom:security non-reentrant only-admin 👽
     */
    function sweepToken(address token) external override nonReentrant advance cygnusAdmin {
        /// @custom:error CantSweepUnderlying Avoid sweeping underlying
        if (token == cygToken) {
            revert PillarsOfCreation__CantSweepUnderlying({token: token, underlying: cygToken});
        }

        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = token.balanceOf(address(this));

        // Transfer token
        token.safeTransfer(msg.sender, balance);

        /// @custom:event SweepToken
        emit SweepToken(token, msg.sender, balance, getCurrentEpoch());
    }

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

        /// @custom:error CygPerBlockExceedsLimit Avoid setting above limit
        if (cygPerBlockRewards > MAX_CYG_PER_BLOCK || cygPerBlockDAO > MAX_CYG_PER_BLOCK)
            revert PillarsOfCreation__CygPerBlockExceedsLimit();

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

        /// @custom:event NewEpoch
        emit NewEpoch(0, 0, 0, cygPerBlockRewards);
    }
}
