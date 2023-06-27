//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusComplexRewarder.sol
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
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                           .⠀
           🛰️          ███ ░███  ███ ░███                .                 .                 .⠀
        .             ░░██████  ░░██████                🛰️                             .                 .     
                       ░░░░░░    ░░░░░░      -------=========*         🛰️             .                     ⠀
           .                            .       .          .            .                        .             .⠀
        
        CYG Complex Rewarder - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusComplexRewarder} from "./interfaces/ICygnusComplexRewarder.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {IERC20} from "./interfaces/core/IERC20.sol";
import {ICygnusTerminal} from "./interfaces/core/ICygnusTerminal.sol";

/**
 *  @notice Main contract used by Cygnus Protocol to reward users in CYG. It is similar to a masterchef contract
 *          but the rewards are based on epochs. Each epoch the rewards get reduced by the `REDUCTION_FACTOR_PER_EPOCH`
 *          which is set at 2.5%. When deploying, the contract calculates the initial rewards per block based on:
 *            - the total amount of rewards
 *            - the total number of epochs
 *            - reduction factor.
 *
 *          cygPerBlockAtEpochN = (totalRewards - accumulatedRewards) * reductionFactor / emissionsCurve(epochN)
 *
 *                   1.6M |_______.
 *                        |       |
 *                   1.4M |       |
 *                        |       |                   Example with 3M totalRewards, 5% reduction and 48 epochs
 *                   1.2M |       |
 *                        |       |                                Epochs    |    Rewards
 *                     1M |       |                             -------------|---------------
 *                        |       |                               00 - 11    | 1,583,165.28
 *          rewards  800k |       |_______.                       12 - 23    |   802,985.97
 *                        |       |       |                       24 - 35    |   407,276.79
 *                   600k |       |       |                       36 - 47    |   206,571.96
 *                        |       |       |                                  | 3,000,000.00
 *                   400k |       |       |_______.
 *                        |       |       |       |
 *                   200k |       |       |       |_______.
 *                        |       |       |       |       |
 *                        |_______|_______|_______|_______|_
 *                          00-11   12-23   24-35  36-47
 *                                     epochs
 *
 *          On any interaction the `advance` function is called to check if we can advance to a new epoch. The contract
 *          self-destructs once the final epoch is reached.
 *
 *  @title  CygnusComplexRewarder The contract that rewards used in CYG
 *  @author CygnusDAO
 */
contract CygnusComplexRewarder is ICygnusComplexRewarder, ReentrancyGuard {
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
        uint256 shuttleId;
        uint256 totalShares;
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
        address bonusRewarder;
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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    address[] public override allShuttles;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(uint256 => EpochInfo) public override getEpochInfo;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(address => mapping(Position => ShuttleInfo)) public getShuttleInfo; // Borrowable -> Position = POOL

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(address => mapping(Position => mapping(address => UserInfo))) public override getUserInfo; // Borrowable -> Position -> User Address = USER

    // Constants

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override ACC_PRECISION = 2 ** 160;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override SHARES_PRECISION = 2 ** 96;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override MAX_CYG_PER_BLOCK = 0.475e18; // 15 mil a year

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override BLOCKS_PER_YEAR = 31536000; // Doesn't take into account leap years

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    string public constant override name = "CygnusDAO: Complex Rewarder";

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override DURATION = BLOCKS_PER_YEAR * 4;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override TOTAL_EPOCHS = 96; // ~2 weeks per epoch

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override BLOCKS_PER_EPOCH = DURATION / TOTAL_EPOCHS; // ~30 Days per epoch

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override REDUCTION_FACTOR_PER_EPOCH = 0.025e18; // 2.5% `cygPerblock` reduction per epoch

    // Immutables //

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    IHangar18 public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public immutable override birth;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public immutable override death;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    address public immutable override cygToken;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public immutable override totalCygRewards;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public override cygPerBlock;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public override totalAllocPoint;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public override lastEpochTime;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public override borrowRewardsWeight = 0.80e18;

    /**
     *  @inheritdoc ICygnusComplexRewarder
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
     *  @param _totalRewards The amount of CYG tokens to be distributed by the end of DURATION
     */
    constructor(IHangar18 _hangar18, address _rewardToken, uint256 _totalRewards) {
        // Total CYG to be distributed
        totalCygRewards = _totalRewards;

        // Calculate the cygPerBlock at epoch 0 (start) given totalRewards
        cygPerBlock = calculateCygPerBlock(0);

        /// @custom:error CygPerBlockExceedsLimit Avoid setting above limit
        if (cygPerBlock > MAX_CYG_PER_BLOCK) {
            revert CygnusComplexRewarder__CygPerBlockExceedsLimit({max: MAX_CYG_PER_BLOCK, value: cygPerBlock});
        }

        // Current timestamp
        uint256 _birth = block.timestamp;

        // Set CYG token
        cygToken = _rewardToken;

        // Set factory
        hangar18 = _hangar18;

        // Start epoch
        lastEpochTime = _birth;

        // Timestamp of deployment
        birth = _birth;

        // Timestamp of when the contract self-destructs
        death = _birth + DURATION;

        // Store epoch
        getEpochInfo[0] = EpochInfo({
            epoch: 0,
            start: _birth,
            end: _birth + BLOCKS_PER_EPOCH,
            cygPerBlock: cygPerBlock,
            totalRewards: cygPerBlock * BLOCKS_PER_EPOCH,
            totalClaimed: 0
        });

        /// @custom:event NewEpoch
        emit NewEpoch(0, 0, 0, cygPerBlock);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Controls important parameters in both Collateral and Borrow contracts 👽
     */
    modifier cygnusAdmin() {
        checkAdmin();
        _;
    }

    /**
     *  @custom:modifier onlyEOA Modifier that allows function call only if msg.sender == tx.origin
     */
    modifier onlyEOA() {
        checkEOA();
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
    function checkAdmin() private view {
        // Current admin from the factory
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) {
            revert CygnusComplexRewarder__MsgSenderNotAdmin({admin: admin, sender: msg.sender});
        }
    }

    /**
     *  @notice Reverts if it is not considered an EOA
     */
    function checkEOA() private view {
        /// @custom:error OnlyEOAAllowed Avoid if not called by an externally owned account
        // solhint-disable-next-line
        if (msg.sender != tx.origin) {
            // solhint-disable-next-line
            revert CygnusComplexRewarder__OnlyEOAAllowed({sender: msg.sender, origin: tx.origin});
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function shuttlesLength() public view override returns (uint256) {
        return allShuttles.length;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function getBlockTimestamp() public view override returns (uint256) {
        // Return this block's timestamp
        return block.timestamp;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
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
     *  @inheritdoc ICygnusComplexRewarder
     */
    function emissionsCurve(uint256 epoch) public pure override returns (uint) {
        // Create the emissions curve based on the reduction factor and epoch
        //  totalCygAtN      = (totalRewards - accumulatedRewards) * reductionFactor / emissionsCurve(epoch)
        //
        //  totalCygAtEpoch0 = (3_000_000 * 0.055) / emissionsCurve(0);
        //                   = (3_000_000 * 0.055) / 0.933819993048072263 = 176693.58251950162
        //
        //  totalCygAtEpoch1 = ((3_000_000 - 176693.58251950162) * 0.055) / emissionsCurve(1);
        //                   = (2_823_306.4174804986 * 0.055) / 0.929968246611716680 = 166975.435480929
        //
        //  totalCygAtEpoch2, etc.
        // 1 minus factor
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
     *  @inheritdoc ICygnusComplexRewarder
     */
    function calculateEpochRewards(uint256 epoch) public view override returns (uint256 rewards) {
        // Get cyg per block for the epoch
        uint256 _cygPerBlock = calculateCygPerBlock(epoch);

        // Return total CYG in the epoch
        return _cygPerBlock * BLOCKS_PER_EPOCH;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function calculateCygPerBlock(uint256 epoch) public view override returns (uint256 rewardRate) {
        // Accumulator of previous rewards
        uint256 previousRewards;

        // keep track of rewards
        uint256 rewards;

        // Get total CYG rewards for `epoch`
        for (uint i = 0; i <= epoch; i++) {
            // Calculate rewards for the current epoch
            rewards = (totalCygRewards - previousRewards).fullMulDiv(REDUCTION_FACTOR_PER_EPOCH, emissionsCurve(i));

            // Accumulate CYG rewards released up to this point
            previousRewards += rewards;
        }

        // Return cygPerBlock for `epoch`
        rewardRate = rewards / BLOCKS_PER_EPOCH;
    }

    function getRewardWeights() public view returns (uint256 borrowers, uint256 lenders) {
        // The % of total CYG that is given to borrowers
        borrowers = borrowRewardsWeight;

        // The % given to lenders
        lenders = 1e18 - borrowers;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function pendingCyg(address borrowable, Position position, address borrower) external view override returns (uint256 pending) {
        // Load pool to memory
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable][position];

        // Load user to memory
        UserInfo memory user = getUserInfo[borrowable][position][borrower];

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
            uint256 reward = (timeElapsed * cygPerBlock * shuttle.allocPoint) / totalAllocPoint;

            // Add the calculated reward per share to the accumulated reward per share
            accRewardPerShare = accRewardPerShare + (reward * ACC_PRECISION) / totalShares;
        }

        // Calculate the pending reward for the user, based on their shares and the accumulated reward per share
        pending = uint256(int256((user.shares * accRewardPerShare) / ACC_PRECISION) - (user.rewardDebt));
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
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

    // Simple view functions to get quickly

    /**
     *  @inheritdoc ICygnusComplexRewarder
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
     *  @inheritdoc ICygnusComplexRewarder
     */
    function currentEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate current epoch rewards
        return calculateEpochRewards(currentEpoch);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function previousEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate next epoch rewards
        return currentEpoch == 0 ? 0 : calculateEpochRewards(currentEpoch - 1);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function nextEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate next epoch rewards
        return calculateEpochRewards(currentEpoch + 1);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function blocksThisEpoch() external view override returns (uint256) {
        // Get how far along we are in this epoch in seconds
        return getBlockTimestamp() - lastEpochTime;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function blocksUntilNextEpoch() external view override returns (uint256) {
        // Return seconds left until next epoch
        return BLOCKS_PER_EPOCH - (getBlockTimestamp() - lastEpochTime);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function blocksUntilSupernova() external view override returns (uint256) {
        // Return seconds until death
        return death - getBlockTimestamp();
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function epochProgression() external view override returns (uint256) {
        // Return how far along we are in this epoch scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - lastEpochTime).divWad(BLOCKS_PER_EPOCH);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function totalProgression() external view override returns (uint256) {
        // Return how far along we are in total scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - birth).divWad(DURATION);
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
                uint256 oldCygPerBlock = cygPerBlock;

                // Store new cygPerBlock
                cygPerBlock = calculateCygPerBlock(currentEpoch);

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
                epoch.cygPerBlock = cygPerBlock;

                // Store the planned rewards for this epoch (same as `currentEpochRewards()`)
                epoch.totalRewards = cygPerBlock * BLOCKS_PER_EPOCH;

                /// @custom:event NewEpoch
                emit NewEpoch(currentEpoch - 1, currentEpoch, oldCygPerBlock, cygPerBlock);
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

        // Hail Satan!
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
    function updateShuttlePrivate(address borrowable, Position position) private returns (ShuttleInfo storage shuttle) {
        // Get the pool information
        shuttle = getShuttleInfo[borrowable][position];

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
                uint256 reward = (timeElapsed * cygPerBlock * shuttle.allocPoint) / totalAllocPoint;

                // Update the accumulated reward per share based on the reward distributed
                shuttle.accRewardPerShare += ((reward * ACC_PRECISION) / totalShares);
            }

            // Store last block tiemstamp
            shuttle.lastRewardTime = timestamp;

            /// @custom:event UpdateShuttle
            emit UpdateShuttle(borrowable, timestamp, totalShares, shuttle.accRewardPerShare);
        }
    }

    /**
     *  @notice Updates all pools
     */
    function acceleratePrivate() private {
        // Get array length
        uint256 totalShuttles = shuttlesLength();

        // Gas savings
        address[] memory shuttles = allShuttles;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Update borrowers pool
            updateShuttlePrivate(shuttles[i], Position.BORROWER);

            // Update lenders pool
            updateShuttlePrivate(shuttles[i], Position.LENDER);
        }
    }

    /**
     *  @notice Collects the CYG the msg.sender has accrued and sends to `to`
     *  @param borrowable The address of the borrowable where borrows are stored
     *  @param to The address to send msg.sender's rewards to
     */
    function collectPrivate(address borrowable, Position position, address to) private {
        // Update the pool to ensure the user's reward calculation is up-to-date.
        ShuttleInfo storage shuttle = updateShuttlePrivate(borrowable, position);

        // Retrieve the user's info for the specified borrowable address.
        UserInfo storage user = getUserInfo[borrowable][position][msg.sender];

        // Avoid stack too deep
        uint256 cygAmount;

        {
            // Calculate the user's accumulated reward based on their shares and the pool's accumulated reward per share.
            int256 accumulatedReward = int256((user.shares * shuttle.accRewardPerShare) / ACC_PRECISION);

            // Calculate the pending reward for the user by subtracting their stored reward debt from their accumulated reward.
            cygAmount = uint256(accumulatedReward - user.rewardDebt);

            // If no rewards then return and don't collect
            if (cygAmount == 0) return;

            // Update the user's reward debt to reflect the current accumulated reward.
            user.rewardDebt = accumulatedReward;
        }

        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Update total claimed for this epoch
        getEpochInfo[currentEpoch].totalClaimed += cygAmount;

        // Check that total claimed this epoch is not above the max we can mint for this epoch
        if (getEpochInfo[currentEpoch].totalClaimed > getEpochInfo[currentEpoch].totalRewards) revert();

        // Mint new CYG
        IERC20(cygToken).mint(to, cygAmount);

        /// @custom:event CollectCYG
        emit CollectReward(borrowable, currentEpoch, msg.sender, cygAmount);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function collect(address borrowable, Position position, address to) external override nonReentrant advance {
        // Checks to see if there is any pending CYG to be collected and sends to user
        collectPrivate(borrowable, position, to);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function collectCygAll(Position position, address to) external override nonReentrant advance {
        // Get shuttles array for gas savings
        address[] memory shuttles = allShuttles;

        // Total initialized shuttles
        uint256 totalShuttles = shuttles.length;

        // Loop through each shuttle and check if there is CYG to collect
        for (uint256 i = 0; i < totalShuttles; ) {
            // Collect CYG private for shuttle `i`
            collectPrivate(shuttles[i], position, to);

            // Next iteration
            unchecked {
                i++;
            }
        }
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function trackRewards(address account, uint256 balance, uint256 adjustmentFactor, Position position) external {
        // Escape if account is the zero address
        if (account == address(0)) return;

        // Interactions
        address borrowable = msg.sender;

        // Update the pool information for the borrowable asset
        // Load to storage for gas savings, not updating
        ShuttleInfo storage shuttle = updateShuttlePrivate(borrowable, position);

        // Get the user information for the borrower in the borrowable asset's pool
        UserInfo storage user = getUserInfo[borrowable][position][account];

        // Calculate the new shares for the borrower based on their current borrow balance and borrow index
        uint256 newShares = balance.fullMulDiv(SHARES_PRECISION, adjustmentFactor);

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

        /// @custom:event TrackShuttle
        emit TrackRewards(borrowable, account, balance, adjustmentFactor, position);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-eoa
     */
    function updateShuttle(address borrowable) external override nonReentrant onlyEOA advance {
        // Update the borrower's pool for this borrowable
        updateShuttlePrivate(borrowable, Position.BORROWER);

        // Update the lender's pool for this borrowable
        updateShuttlePrivate(borrowable, Position.LENDER);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-eoa
     */
    function supernova() external override nonReentrant onlyEOA advance {
        // Calls the internal destroy function, anyone can call
        supernovaPrivate();
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-eoa
     */
    function advanceEpoch() external override nonReentrant onlyEOA advance {
        //
        // The advance modifier will loop through each shuttle and update rewards for each borrow/lend pool
        //
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-eoa
     */
    function accelerateTheUniverse() external override nonReentrant onlyEOA advance {
        //
        // The advance modifier will loop through each shuttle and update rewards for each borrow/lend pool
        //
        /// @custom:event AccelerateTheUniverse
        emit AccelerateTheUniverse(shuttlesLength(), msg.sender, getCurrentEpoch());
    }

    /*  ────────── Admin ────────── */

    /**
     *  @notice Bonus rewards are only for borrowers
     */
    function setBonusRewarder(uint256 shuttleId, address bonusRewarder) external nonReentrant advance cygnusAdmin {
        // Retrieve shuttle information from Hangar 18.
        (, , address borrowable, , ) = hangar18.allShuttles(shuttleId);

        // Retrieve the pool information for the specified shuttle's borrowable address.
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable][Position.BORROWER];

        /// @custom:error ShuttleNotInitialized Avoid adjusting rewards for an un-active shuttle
        if (shuttle.active == false) {
            revert CygnusComplexRewarder__ShuttleNotInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Assign bonus shuttle rewards
        shuttle.bonusRewarder = bonusRewarder;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function initializeShuttleRewards(uint256 shuttleId, uint256 allocPoint) external override nonReentrant advance cygnusAdmin {
        // Retrieve shuttle information from Hangar 18.
        (, , address borrowable, , ) = hangar18.allShuttles(shuttleId);

        // Retrieve the pool information for the specified shuttle's borrowable address.
        ShuttleInfo storage borrowRewards = getShuttleInfo[borrowable][Position.BORROWER];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (borrowRewards.active == true) {
            revert CygnusComplexRewarder__ShuttleAlreadyInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Create lending rewards too
        ShuttleInfo storage lenderRewards = getShuttleInfo[borrowable][Position.LENDER];

        // Update the total allocation point by subtracting the old allocation point and adding the new one for the specified pool.
        totalAllocPoint += allocPoint;

        // Set as active, can't be set to false again
        borrowRewards.active = true;

        // Mark lender rewards as active also
        lenderRewards.active = true;

        // Assign shuttle ID (the ID of the lending pools)
        borrowRewards.shuttleId = shuttleId;

        // Same as borrower's since it's the same lending pool
        lenderRewards.shuttleId = shuttleId;

        // Update the allocation point for the specified pools
        borrowRewards.allocPoint = allocPoint.mulWad(borrowRewardsWeight);

        // lenderRewards = 100% - borrowRewards
        lenderRewards.allocPoint = allocPoint - borrowRewards.allocPoint;

        // Push to array
        allShuttles.push(borrowable);

        /// @custom:event NewShuttleReward
        emit NewShuttleReward(shuttleId, borrowable, allocPoint);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function adjustShuttleRewards(uint256 shuttleId, uint256 allocPoint) external override advance cygnusAdmin {
        // Retrieve shuttle information from Hangar 18.
        (, , address borrowable, , ) = hangar18.allShuttles(shuttleId);

        // Retrieve the pool information for the specified shuttle's borrowable address.
        ShuttleInfo storage borrowRewards = getShuttleInfo[borrowable][Position.BORROWER];

        /// @custom:error ShuttleNotInitialized Avoid adjusting rewards for an un-active shuttle
        if (borrowRewards.active == false) {
            revert CygnusComplexRewarder__ShuttleNotInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Retrieve the pool information for the specified shuttle's borrowable address.
        ShuttleInfo storage lenderRewards = getShuttleInfo[borrowable][Position.LENDER];

        // Get previous alloc
        uint256 previousAlloc = borrowRewards.allocPoint + lenderRewards.allocPoint;

        // Update the total allocation point by subtracting the old allocation point and adding the new one for the specified pool.
        totalAllocPoint = (totalAllocPoint - previousAlloc) + allocPoint;

        // Update the allocation point for borrow rewards
        borrowRewards.allocPoint = allocPoint.mulWad(borrowRewardsWeight);

        // Update the allocation point for lender rewards
        lenderRewards.allocPoint = allocPoint - borrowRewards.allocPoint;

        /// @custom:event NewShuttleAllocPoint
        emit NewShuttleAllocPoint(shuttleId, borrowable, previousAlloc, allocPoint);
    }

    /**
     *  @notice This shouldn't be used but we keep it in case we need to manually update the `cygPerBlock`
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function setRewardWeights(uint256 _borrowRewardsWeight) external override advance cygnusAdmin {
        /// @custom:error InvalidTotalWeight
        if (_borrowRewardsWeight > 1e18) revert CygnusComplexRewarder__InvalidTotalWeight();

        // Update weight
        borrowRewardsWeight = _borrowRewardsWeight;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function sweepToken(address token) external override nonReentrant advance cygnusAdmin {
        /// @custom:error CantSweepUnderlying Avoid sweeping underlying
        if (token == cygToken) {
            revert CygnusComplexRewarder__CantSweepUnderlying({token: token, underlying: cygToken});
        }

        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = token.balanceOf(address(this));

        // Transfer token
        token.safeTransfer(msg.sender, balance);

        /// @custom:event SweepToken
        emit SweepToken(token, msg.sender, balance, getCurrentEpoch());
    }

    /**
     *  @notice This shouldn't be used but we keep it in case we need to manually update the `cygPerBlock`
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function setCygPerBlock(uint256 _cygPerBlock) external override advance cygnusAdmin {
        /// @custom:error CygPerBlockExceedsLimit Avoid setting above limit
        if (_cygPerBlock > MAX_CYG_PER_BLOCK) {
            revert CygnusComplexRewarder__CygPerBlockExceedsLimit({max: MAX_CYG_PER_BLOCK, value: _cygPerBlock});
        }

        // Previous rate
        uint256 lastCygPerBlock = cygPerBlock;

        // The cygPerBlock will reset to the original curve when new epoch starts.
        cygPerBlock = _cygPerBlock;

        /// @custom:event NewCygPerBlock
        emit NewCygPerBlock(lastCygPerBlock, _cygPerBlock);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security only-admin 👽
     */
    function setDoomSwitch() external override advance cygnusAdmin {
        // Set the doom switch, cannot be turned off!
        doomSwitch = true;
    }
}
