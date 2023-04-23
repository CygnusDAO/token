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

// CYG rewarder
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
     *  @custom:struct StarInfo Info of each borrowable
     *  @custom:member totalShares The total number of shares held in the pool
     *  @custom:member accRewardPerShare The accumulated reward per share of the pool
     *  @custom:member lastRewardTime The timestamp of the last reward distribution
     *  @custom:member allocPoint The allocation points of the pool
     */
    struct StarInfo {
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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(address => StarInfo) public override getStarInfo;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(address => mapping(address => UserInfo)) public override getUserInfo;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    mapping(uint256 => EpochInfo) public override getEpochInfo;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    address[] public override allStars;

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
    uint256 public constant override EPOCH_DURATION = DURATION / TOTAL_EPOCHS; // ~30 Days per epoch

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
    uint256 public override totalCyg;

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    uint256 public override cygClaimed;

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
        totalCyg = _totalRewards;

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
          end : _birth + EPOCH_DURATION,
          rewardRate: cygPerBlock,
          totalRewards: cygPerBlock * EPOCH_DURATION,
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
     *  @custom:modifier advance Updates epoch if necessary
     */
    modifier advance() {
        advanceEpochPrivate();
        _;
    }

    /**
     *  @custom:modifier onlyEOA Modifier that allows function call only if msg.sender == tx.origin
     */
    modifier onlyEOA() {
        checkEOA();
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
    function starsLength() public view override returns (uint256) {
        return allStars.length;
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
    function emissionsCurve(uint256 epoch) public pure override returns (uint) {
        // Create the emissions curve based on the reduction factor and epoch
        //  ie. totalRewards    = 3,000,000
        //      reductionFactor = 5.5%
        //      totalEpochs     = 48;
        //      totalCygAtN     = totalRewards - accumulatedRewards * reductionFactor / emissionsCurve(epoch)
        //
        //  totalCygAtEpoch0 = (3_000_000 * 0.055) / emissionsCurve(0);
        //                   = (3_000_000 * 0.055) / 0.933819993048072263
        //                   = 176693.58251950162
        //
        //  totalCygAtEpoch1 = ((3_000_000 - 176693.58251950162) * 0.055) / emissionsCurve(1);
        //                   = (2_823_306.4174804986 * 0.055) / 0.929968246611716680
        //                   = 166975.435480929
        //
        //  totalCygAtEpoch2 = ((3_000_000 - (176693.58251950162 + 166975.435480929)) * 0.055) / emissionsCurve(2);
        //                   = (3_000_000 * 0.055) / 0.925892324456843047
        //                   = 157791.78652947795
        //
        //  totalCygAtEpoc3, etc.
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
        // Accumulator
        uint256 previousRewards;

        // Escape
        if (epoch >= TOTAL_EPOCHS) {
            return 0;
        }

        // epochRewards = (totalCygLeft * reductionPerEpoch) / (1 - (1 - reductionPerEpoch ** (totalEpochs - i))
        for (uint i = 0; i <= epoch; i++) {
            // Calculate rewards for the current epoch
            rewards = (totalCyg - previousRewards).mul(REDUCTION_FACTOR_PER_EPOCH).div(emissionsCurve(i));

            // Accumulate CYG rewards released up to this point
            previousRewards += rewards;
        }
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function calculateCygPerBlock(uint256 epoch) public view override returns (uint256 _rewardRate) {
        // Accumulator of previous rewards
        uint256 previousRewards;

        // keep track of rewards
        uint256 rewards;

        // Escape
        if (epoch >= TOTAL_EPOCHS) {
            return 0;
        }

        // Get total CYG rewards for `epoch`
        for (uint i = 0; i <= epoch; i++) {
            // Calculate rewards for the current epoch
            rewards = (totalCyg - previousRewards).mul(REDUCTION_FACTOR_PER_EPOCH).div(emissionsCurve(i));

            // Accumulate CYG rewards released up to this point
            previousRewards += rewards;
        }

        // Return cygPerBlock for `epoch`
        _rewardRate = rewards / EPOCH_DURATION;
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
        currentEpoch = (currentTime - birth) / EPOCH_DURATION;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function pendingCyg(address borrowable, address _user) external view override returns (uint256 pending) {
        // Load pool to memory
        StarInfo memory star = getStarInfo[borrowable];

        // Load user to memory
        UserInfo memory user = getUserInfo[borrowable][_user];

        // Load the accumulated reward per share
        uint256 accRewardPerShare = star.accRewardPerShare;

        // Load total shares from the pool
        uint256 totalShares = star.totalShares;

        // Current timestamp
        uint256 timestamp = getBlockTimestamp();

        // If the current block's timestamp is after the last reward time and there are shares in the pool
        if (timestamp > star.lastRewardTime && totalShares != 0) {
            // Calculate the time elapsed since the last reward
            uint256 timeElapsed = timestamp - star.lastRewardTime;

            // Calculate the reward for the elapsed time, using the pool's allocation point and total allocation points
            uint256 reward = (timeElapsed * cygPerBlock * star.allocPoint) / totalAllocPoint;

            // Add the calculated reward per share to the accumulated reward per share
            accRewardPerShare = accRewardPerShare + (reward * ACC_PRECISION) / totalShares;
        }

        // Calculate the pending reward for the user, based on their shares and the accumulated reward per share
        pending = ((user.shares * accRewardPerShare) / ACC_PRECISION) - uint256(user.rewardDebt);
    }

    // Simple view functions to get quickly

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
    function epochProgression() external view override returns (uint256) {
        // Return how far along we are in this epoch scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - lastEpochTime).div(EPOCH_DURATION);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function totalProgression() external view override returns (uint256) {
        // Return how far along we are in total scaled by 1e18 (0.69e18 = 69%)
        return (getBlockTimestamp() - birth).div(DURATION);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function timeUntilSupernova() external view override returns (uint256) {
        // Return seconds until death
        return death - getBlockTimestamp();
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     */
    function timeUntilNextEpoch() external view override returns (uint256) {
        // Return seconds left until next epoch
        return EPOCH_DURATION - (getBlockTimestamp() - lastEpochTime);
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
        uint256 epochsPassed = timeSinceLastEpoch / EPOCH_DURATION;

        // Update if we are at new epoch
        if (epochsPassed > 0) {
            // Get this epoch
            uint256 currentEpoch = getCurrentEpoch();

            // New epoch
            uint256 newEpoch = currentEpoch + epochsPassed;

            // Check that contract is not expired
            if (newEpoch < TOTAL_EPOCHS) {
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
                epoch.end = currentTime + EPOCH_DURATION;

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
        // Check if it's not yet time to destroy the contract
        if (getBlockTimestamp() < death) return;

        // Get the current admin from the factory
        address admin = hangar18.admin();

        /// @custom:event Supernova
        emit Supernova(_msgSender(), birth, death, getBlockTimestamp());

        // Destroy the contract and transfer remaining funds to the admin
        selfdestruct(payable(admin));
    }

    /**
     *  @dev Updates the pool's accumulated CYG reward per share and distributes rewards.
     *  @param borrowable Address of the borrowable contract.
     *  @return star The updated pool information.
     */
    function updateStarPrivate(address borrowable) private returns (StarInfo memory star) {
        // Get the pool information
        star = getStarInfo[borrowable];

        // Current timestamp
        uint256 timestamp = getBlockTimestamp();

        // Check if rewards can be distributed
        if (timestamp > star.lastRewardTime) {
            // Calculate the reward to be distributed
            uint256 totalShares = star.totalShares;

            if (totalShares > 0) {
                // Calculate the time elapsed since the last reward distribution
                uint256 timeElapsed = timestamp - star.lastRewardTime;

                // Calculate the reward to be distributed based on the time elapsed and the pool's allocation point
                uint256 reward = (timeElapsed * cygPerBlock * star.allocPoint) / totalAllocPoint;

                // Update the accumulated reward per share based on the reward distributed
                star.accRewardPerShare = star.accRewardPerShare + ((reward * ACC_PRECISION) / totalShares);
            }

            // Store last block tiemstamp
            star.lastRewardTime = timestamp;

            // Update pool
            getStarInfo[borrowable] = star;

            /// @custom:event UpdateRift
            emit UpdateStar(borrowable, timestamp, totalShares, star.accRewardPerShare);
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function collect(address borrowable, address to) public override nonReentrant advance {
        // Update the pool to ensure the user's reward calculation is up-to-date.
        StarInfo memory star = updateStarPrivate(borrowable);

        // Retrieve the user's info for the specified borrowable address.
        UserInfo storage user = getUserInfo[borrowable][_msgSender()];

        // Calculate the user's accumulated reward based on their shares and the pool's accumulated reward per share.
        int256 accumulatedReward = int256((user.shares * star.accRewardPerShare) / ACC_PRECISION);

        // Calculate the pending reward for the user by subtracting their stored reward debt from their accumulated reward.
        uint256 newRewards = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        // Update the user's reward debt to reflect the current accumulated reward.
        user.rewardDebt = accumulatedReward;

        // Interactions
        // Transfer the user's pending reward to the specified recipient address, if it is greater than zero.
        if (newRewards != 0) {
            // Transfer CYG
            cygToken.safeTransfer(to, newRewards);

            // Add to claimed
            cygClaimed += newRewards;

            // Claim
            getEpochInfo[getCurrentEpoch()].totalClaimed += newRewards;
        }

        /// @custom:event CollectCYG
        emit CollectReward(borrowable, _msgSender(), newRewards);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function trackBorrow(
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
        StarInfo memory star = updateStarPrivate(borrowable);

        // Get the user information for the borrower in the borrowable asset's pool
        UserInfo storage user = getUserInfo[borrowable][borrower];

        // Calculate the new shares for the borrower based on their current borrow balance and borrow index
        uint256 newShares = (borrowBalance * SHARES_PRECISION) / borrowIndex;

        // Calculate the difference in shares for the borrower and update their shares
        int256 diffShares = int256(newShares) - int256(user.shares);

        // Calculate the difference in reward debt for the borrower and update their reward debt
        int256 diffRewardDebt = (diffShares * int256(star.accRewardPerShare)) / int256(ACC_PRECISION);

        // Update shares
        user.shares = newShares;

        // Update reward debt
        user.rewardDebt = user.rewardDebt + diffRewardDebt;

        // Update the total shares of the borrowable asset's pool
        getStarInfo[borrowable].totalShares = uint256(int256(star.totalShares) + diffShares);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function updateStar(address borrowable) external override nonReentrant advance {
        // Update pool
        updateStarPrivate(borrowable);
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function supernova() external override nonReentrant advance onlyEOA {
        // Calls the internal destroy function, anyone can call
        supernovaPrivate();
    }

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function advanceEpoch() external override nonReentrant advance onlyEOA {}

    /**
     *  @inheritdoc ICygnusComplexRewarder
     *  @custom:security non-reentrant
     */
    function accelerateTheUniverse() external override nonReentrant advance {
        // Get array length
        uint256 totalShuttles = starsLength();

        // Gas savings
        address[] memory stars = allStars;

        // Loop through stars array and update all pools
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Update star
            updateStarPrivate(stars[i]);
        }
    }

    /*  ────────── Admin  */

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
        StarInfo storage star = getStarInfo[borrowable];

        /// @custom:error ShuttleAlreadyInitialized Avoid initializing twice
        if (star.allocPoint != 0) {
            revert CygnusComplexRewarder__ShuttleAlreadyInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Update the total allocation point by subtracting the old allocation point and adding the new one for the specified pool.
        totalAllocPoint += allocPoint;

        // Update the allocation point for the specified pool.
        star.allocPoint = allocPoint;

        // Push to array
        allStars.push(borrowable);

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
        StarInfo storage star = getStarInfo[borrowable];

        /// @custom:error ShuttleNotInitialized Avoid initializing twice
        if (star.allocPoint == 0) {
            revert CygnusComplexRewarder__ShuttleNotInitialized({shuttleId: shuttleId, borrowable: borrowable});
        }

        // Get previous alloc
        uint256 previousAlloc = star.allocPoint;

        // Update the total allocation point by subtracting the old allocation point and adding the new one for the specified pool.
        totalAllocPoint = (totalAllocPoint - star.allocPoint) + allocPoint;

        // Update the allocation point for the specified pool.
        star.allocPoint = allocPoint;

        /// @custom:event NewShuttleAllocPoint
        emit NewShuttleAllocPoint(shuttleId, borrowable, previousAlloc, allocPoint);
    }

    /**
     *  @notice This shouldn't be used but we keep it in case we need to manually update the `cygPerBlock`
     *  @notice The cygPerBlock resets to the original curve when new epoch starts
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

    /*
     *  epoch #00:  924647.902572138   2023/H1
     *  epoch #06:  658517.377429733   2023/H2
     *  epoch #12:  468984.069688193   2024/H1
     *  epoch #18:  334001.903609247   2024/H2
     *  epoch #24:  237870.066010495   2025/H1
     *  epoch #30:  169406.724010870   2025/H2
     *  epoch #36:  120648.380106932   2026/H1
     *  epoch #42:  85923.5765723960   2026/H2
     */
}
