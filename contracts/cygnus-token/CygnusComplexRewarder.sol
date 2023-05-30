// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusComplexRewarder} from "./interfaces/ICygnusComplexRewarder.sol";
import {Context} from "./utils/Context.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {PRBMathUD60x18, PRBMath} from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {IERC20} from "./interfaces/core/IERC20.sol";

/**
 *  @notice Main contract used by Cygnus Protocol to reward users in CYG. It is similar to a masterchef contract
 *          but the rewards are based on epochs. Each epoch the rewards get reduced by the `REDUCTION_FACTOR_PER_EPOCH`
 *          which we set at 5.5%. When deploying, the contract calculates the initial rewards per block based on: 
 *            - the total amount of rewards
 *            - the total number of epochs
 *            - reduction factor. 
 *         
 *          cygPerBlockAtEpochN = (totalRewards - accumulatedRewards) * reductionFactor / emissionsCurve(epochN)
 *
 *          For example total rewards of 3,000,000 will be:
 *
 *                   1.6M |_______.
 *                        |       |
 *                   1.4M |       |
 *                        |       |
 *                   1.2M |       |
 *                        |       |                                Epochs    |    Rewards
 *                     1M |       |                             -------------|---------------
 *                        |       |                               00 - 11    | 1,583,165.28
 *          rewards  800k |       |_______.                       12 - 23    |   802,985.97
 *                        |       |       |                       24 - 35    |   407,276.79
 *                   600k |       |       |                       36 - 47    |   206,571.96
 *                        |       |       |                                    3,000,000.00
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
contract CygnusComplexRewarder is ICygnusComplexRewarder, Context, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library PRBMathUD60x18 Library for advanced fixed-point math that works with uint256 numbers
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @custom:struct Epoch Information on each epoch
     *  @custom:member epoch The ID for this epoch
     *  @custom:member rewardRate The CYG reward rate for this epoch
     *  @custom:member totalRewards The total amount of CYG estimated to be rewarded in this epoch
     *  @custom:member totalClaimed The total amount of claimed CYG
     *  @custom:member start The unix timestamp of when this epoch started
     *  @custom:member end The unix timestamp of when it ended or is estimated to end
     */
    struct EpochInfo {
        uint256 epoch;
        uint256 rewardRate;
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
     *  @custom:member accRewardPerShare The accumulated reward per share of the pool
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
    mapping(address => ShuttleInfo) public override getShuttleInfo;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(address => mapping(address => UserInfo)) public override getUserInfo;

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
    uint256 public constant override BLOCKS_PER_YEAR = 31536000;

    // Customizable

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    string public constant override name = "CYG Complex Rewarder";

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override DURATION = BLOCKS_PER_YEAR * 4; // 126144000

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override TOTAL_EPOCHS = 48; // 1 month per epoch

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override BLOCKS_PER_EPOCH = DURATION / TOTAL_EPOCHS; // ~30 Days per epoch

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public constant override REDUCTION_FACTOR_PER_EPOCH = 0.055e18; // 5.5% `cygPerblock` reduction per epoch

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

    // USed for calculating epoch rewards //

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
    uint256 public override totalCygRewards;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Constructor that initializes the contract with the given `_hangar18`, `_rewardToken`, and `_cygPerBlock` values.
     *
     *  @param _hangar18 The address of the Hangar18 contract.
     *  @param _rewardToken The address of the reward token contract.
     *  @param _totalRewards The amount of CYG tokens to be distributed by the end of DURATION
     *
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
            rewardRate: cygPerBlock,
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
        // Advance epoch first
        advanceEpochPrivate();
        _;
        // Check to self destruct
        supernovaPrivate();
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
        if (_msgSender() != admin) {
            revert CygnusComplexRewarder__MsgSenderNotAdmin({admin: admin, sender: _msgSender()});
        }
    }

    /**
     *  @notice Reverts if it is not considered an EOA
     */
    function checkEOA() private view {
        /// @custom:error OnlyEOAAllowed Avoid if not called by an externally owned account
        // solhint-disable-next-line
        if (_msgSender() != tx.origin) {
            // solhint-disable-next-line
            revert CygnusComplexRewarder__OnlyEOAAllowed({sender: _msgSender(), origin: tx.origin});
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

        // If time is after death return total epochs
        if (currentTime >= death) {
            // Contract has expired
            return TOTAL_EPOCHS;
        }

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
            result = result.mul(oneMinusReductionFactor);
        }

        // 1 minus the result
        return 1e18 - result;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function calculateEpochRewards(uint256 epoch) public view override returns (uint256 rewards) {
        // Accumulator of previous rewards
        uint256 previousRewards;

        // epochRewards = (totalRewards - accumulatedRewards) * reductionFactor / emissionsCurve(epoch)
        for (uint i = 0; i <= epoch; i++) {
            // Calculate rewards for the current epoch
            rewards = (totalCygRewards - previousRewards).mul(REDUCTION_FACTOR_PER_EPOCH).div(emissionsCurve(i));

            // Accumulate CYG rewards released up to this point
            previousRewards += rewards;
        }
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
            rewards = (totalCygRewards - previousRewards).mul(REDUCTION_FACTOR_PER_EPOCH).div(emissionsCurve(i));

            // Accumulate CYG rewards released up to this point
            previousRewards += rewards;
        }

        // Return cygPerBlock for `epoch`
        rewardRate = rewards / BLOCKS_PER_EPOCH;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function pendingCyg(address borrowable, address borrower) external view override returns (uint256 pending) {
        // Load pool to memory
        ShuttleInfo memory shuttle = getShuttleInfo[borrowable];

        // Load user to memory
        UserInfo memory user = getUserInfo[borrowable][borrower];

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
        uint256 epochProgress = (getBlockTimestamp() - lastEpochTime).div(BLOCKS_PER_EPOCH);

        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Total rewards this epoch
        uint256 rewards = getEpochInfo[currentEpoch].totalRewards;

        // Claimed rewards this epoch
        uint256 claimed = getEpochInfo[currentEpoch].totalClaimed;

        // Get rewards claimed progress relative to epoch progress. ie. epoch progression is 50% and 50%
        // of rewards in this epoch have been claimed then we are at 100% or 1e18
        return claimed.div(rewards).div(epochProgress);
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
    function nextEpochRewards() external view override returns (uint256) {
        // Get current epoch
        uint256 currentEpoch = getCurrentEpoch();

        // Calculate next epoch rewards
        return calculateEpochRewards(currentEpoch + 1);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function distanceThisEpoch() external view override returns (uint256) {
        // Get how far along we are in this epoch in seconds
        return getBlockTimestamp() - lastEpochTime;
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function distanceUntilNextEpoch() external view override returns (uint256) {
        // Return seconds left until next epoch
        return BLOCKS_PER_EPOCH - (getBlockTimestamp() - lastEpochTime);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function distanceUntilSupernova() external view override returns (uint256) {
        // Return seconds until death
        return death - getBlockTimestamp();
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function epochProgression() external view override returns (uint256) {
        // Return how far along we are in this epoch scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - lastEpochTime).div(BLOCKS_PER_EPOCH);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function totalProgression() external view override returns (uint256) {
        // Return how far along we are in total scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - birth).div(DURATION);
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
                epoch.rewardRate = cygPerBlock;

                // Store the planned rewards for this epoch (same as `currentEpochRewards`)
                epoch.totalRewards = calculateEpochRewards(currentEpoch);

                /// @custom:event NewEpoch
                emit NewEpoch(currentEpoch - 1, currentEpoch, oldCygPerBlock, cygPerBlock);
            }
        }
    }

    /**
     * @dev Internal function that destroys the contract and transfers remaining funds to the owner.
     */
    function supernovaPrivate() private {
        // Get epoch, uses block.timestamp - keep this function separate to getCurrentEpoch for simplicity
        uint256 epoch = getCurrentEpoch();

        // Check if current epoch is less than total epochs
        if (epoch < TOTAL_EPOCHS) {
            return;
        }

        // Get the current admin from the factory
        address admin = hangar18.admin();

        /// @custom:event Supernova
        emit Supernova(_msgSender(), birth, death, epoch);

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
    function updateShuttlePrivate(address borrowable) private returns (ShuttleInfo memory shuttle) {
        // Get the pool information
        shuttle = getShuttleInfo[borrowable];

        // Current timestamp
        uint256 timestamp = getBlockTimestamp();

        // Check if rewards can be distributed
        if (timestamp > shuttle.lastRewardTime) {
            // Calculate the reward to be distributed
            uint256 totalShares = shuttle.totalShares;

            if (totalShares > 0) {
                // Calculate the time elapsed since the last reward distribution
                uint256 timeElapsed = timestamp - shuttle.lastRewardTime;

                // Calculate the reward to be distributed based on the time elapsed and the pool's allocation point
                uint256 reward = (timeElapsed * cygPerBlock * shuttle.allocPoint) / totalAllocPoint;

                // Update the accumulated reward per share based on the reward distributed
                shuttle.accRewardPerShare = shuttle.accRewardPerShare + ((reward * ACC_PRECISION) / totalShares);
            }

            // Store last block tiemstamp
            shuttle.lastRewardTime = timestamp;

            // Update pool
            getShuttleInfo[borrowable] = shuttle;

            /// @custom:event UpdateShuttle
            emit UpdateShuttle(borrowable, timestamp, totalShares, shuttle.accRewardPerShare);
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function collect(address borrowable, address to) public override nonReentrant advance {
        // Update the pool to ensure the user's reward calculation is up-to-date.
        ShuttleInfo memory shuttle = updateShuttlePrivate(borrowable);

        // Retrieve the user's info for the specified borrowable address.
        UserInfo storage user = getUserInfo[borrowable][_msgSender()];

        // Calculate the user's accumulated reward based on their shares and the pool's accumulated reward per share.
        int256 accumulatedReward = int256((user.shares * shuttle.accRewardPerShare) / ACC_PRECISION);

        // Calculate the pending reward for the user by subtracting their stored reward debt from their accumulated reward.
        uint256 newRewards = uint256(accumulatedReward - user.rewardDebt);

        // Update the user's reward debt to reflect the current accumulated reward.
        user.rewardDebt = accumulatedReward;

        // Transfer the user's pending reward to the specified recipient address, if it is greater than zero.
        if (newRewards != 0) {
            // Get current epoch
            uint256 currentEpoch = getCurrentEpoch();

            // Claim
            getEpochInfo[currentEpoch].totalClaimed += newRewards;

            // Transfer CYG
            cygToken.safeTransfer(to, newRewards);
        }

        /// @custom:event CollectCYG
        emit CollectReward(borrowable, _msgSender(), newRewards);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function trackBorrower(
        uint256 shuttleId,
        address borrower,
        uint borrowBalance,
        uint borrowIndex
    ) external override nonReentrant advance {
        // Get borrowable contract
        (, , address borrowable, , ) = hangar18.allShuttles(shuttleId);

        /// @custom:error MsgSenderNotBorrowable Only the borrowable contract can call this function
        if (_msgSender() != borrowable) {
            revert CygnusComplexRewarder__MsgSenderNotBorrowable({borrowable: borrowable, sender: _msgSender()});
        }

        // Interactions
        // Update the pool information for the borrowable asset
        ShuttleInfo memory shuttle = updateShuttlePrivate(borrowable);

        // Get the user information for the borrower in the borrowable asset's pool
        UserInfo storage user = getUserInfo[borrowable][borrower];

        // Calculate the new shares for the borrower based on their current borrow balance and borrow index
        uint256 newShares = (borrowBalance * SHARES_PRECISION) / borrowIndex;

        // Calculate the difference in shares for the borrower and update their shares
        int256 diffShares = int256(newShares) - int256(user.shares);

        // Calculate the difference in reward debt for the borrower and update their reward debt
        int256 diffRewardDebt = (diffShares * int256(shuttle.accRewardPerShare)) / int256(ACC_PRECISION);

        // Update shares
        user.shares = newShares;

        // Update reward debt
        user.rewardDebt = user.rewardDebt + diffRewardDebt;

        // Update the total shares of the borrowable asset's pool
        getShuttleInfo[borrowable].totalShares = uint256(int256(shuttle.totalShares) + diffShares);

        /// @custom:event TrackShuttle
        emit TrackShuttle(borrowable, borrower, borrowBalance, borrowIndex);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function accelerateTheUniverse() external override nonReentrant advance {
        // Get array length
        uint256 totalShuttles = shuttlesLength();

        // Gas savings
        address[] memory shuttles = allShuttles;

        // Loop through each shuttle
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Update shuttle
            updateShuttlePrivate(shuttles[i]);
        }

        /// @custom:event AccelerateTheUniverse
        emit AccelerateTheUniverse(totalShuttles, _msgSender(), getCurrentEpoch());
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function updateShuttle(address borrowable) external override nonReentrant advance {
        // Update pool
        updateShuttlePrivate(borrowable);
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
    function advanceEpoch() external override nonReentrant onlyEOA advance {}

    /*  ────────── Admin ────────── */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function initializeShuttleRewards(
        uint256 shuttleId,
        uint256 allocPoint
    ) external override nonReentrant advance cygnusAdmin {
        // Retrieve shuttle information from Hangar 18.
        (, , address borrowable, , ) = hangar18.allShuttles(shuttleId);

        // Retrieve the pool information for the specified shuttle's borrowable address.
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (shuttle.active == true) {
            revert CygnusComplexRewarder__ShuttleAlreadyInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Update the total allocation point by subtracting the old allocation point and adding the new one for the specified pool.
        totalAllocPoint += allocPoint;

        // Set as active, can't be set to false again
        shuttle.active = true;

        // Unique ID
        shuttle.shuttleId = shuttleId;

        // Update the allocation point for the specified pool.
        shuttle.allocPoint = allocPoint;

        // Push to array
        allShuttles.push(borrowable);

        /// @custom:event NewShuttleReward
        emit NewShuttleReward(shuttleId, borrowable, allocPoint);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function adjustShuttleRewards(
        uint256 shuttleId,
        uint256 allocPoint
    ) external override nonReentrant advance cygnusAdmin {
        // Retrieve shuttle information from Hangar 18.
        (, , address borrowable, , ) = hangar18.allShuttles(shuttleId);

        // Retrieve the pool information for the specified shuttle's borrowable address.
        ShuttleInfo storage shuttle = getShuttleInfo[borrowable];

        /// @custom:error ShuttleNotInitialized Avoid adjusting rewards for an un-active shuttle
        if (shuttle.active == false) {
            revert CygnusComplexRewarder__ShuttleNotInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Get previous alloc
        uint256 previousAlloc = shuttle.allocPoint;

        // Update the total allocation point by subtracting the old allocation point and adding the new one for the specified pool.
        totalAllocPoint = (totalAllocPoint - shuttle.allocPoint) + allocPoint;

        // If alloc point is 0 then remove from array
        if (allocPoint == 0) {
            // Set to false
            shuttle.active = false;

            // Get array length
            uint256 totalShuttles = shuttlesLength();

            // Gas savings
            address[] memory _allShuttles = allShuttles;

            // Loop through each shuttle and if shuttle is borrowable pop from array
            for (uint256 i; i < totalShuttles; i++) {
                // Check if borrowable
                if (borrowable == _allShuttles[i]) {
                    // Move to last index of array
                    allShuttles[i] = allShuttles[totalShuttles - 1];

                    // Pop from array but don't delete from mapping
                    allShuttles.pop();

                    // Exit loop
                    break;
                }
            }
        }

        // Update the allocation point for the specified pool.
        shuttle.allocPoint = allocPoint;

        /// @custom:event NewShuttleAllocPoint
        emit NewShuttleAllocPoint(shuttleId, borrowable, previousAlloc, allocPoint);
    }

    /**
     *  @notice This shouldn't be used but we keep it in case we need to manually update the `cygPerBlock`
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant only-admin 👽
     */
    function setCygPerBlock(uint256 _cygPerBlock) external override nonReentrant advance cygnusAdmin {
        /// @custom:error CygPerBlockExceedsLimit Avoid setting above limit
        if (_cygPerBlock > MAX_CYG_PER_BLOCK) {
            revert CygnusComplexRewarder__CygPerBlockExceedsLimit({max: MAX_CYG_PER_BLOCK, value: _cygPerBlock});
        }

        // Previous rate
        uint256 lastCygPerBlock = cygPerBlock;

        // Assign new cyg per block
        // The cygPerBlock will reset to the original curve when new epoch starts
        cygPerBlock = _cygPerBlock;

        /// @custom:event NewCygPerBlock
        emit NewCygPerBlock(lastCygPerBlock, _cygPerBlock);
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
        token.safeTransfer(_msgSender(), balance);

        /// @custom:event SweepToken
        emit SweepToken(token, _msgSender(), balance, getCurrentEpoch());
    }
}
