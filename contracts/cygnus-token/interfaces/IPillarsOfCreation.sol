// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Interfaces
import {IHangar18} from "./core/IHangar18.sol";
import {IBonusRewarder} from "./IBonusRewarder.sol";

/**
 *  @notice Interface to interact with CYG rewards
 */
interface IPillarsOfCreation {
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
     *  @custom:member bonusRewarder The address of the bonus rewarder contract (if set)
     *  @custom:member pillarsId Unique ID of the rewards to separate shuttle ID between lenders/borrowers
     */
    struct ShuttleInfo {
        bool active;
        uint256 shuttleId;
        address borrowable;
        address collateral;
        uint256 totalShares;
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
        uint256 allocPoint;
        IBonusRewarder bonusRewarder;
        uint256 pillarsId;
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

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts if initializing pillars again
     *
     *  @custom:error PillarsAlreadyInitialized
     */
    error PillarsOfCreation__PillarsAlreadyInitialized();

    /**
     *  @dev Reverts if caller is not the Hangar18 Admin
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error PillarsOfCreation__MsgSenderNotAdmin();

    /**
     *  @dev Reverts if pool is not initialized in the rewarder
     *
     *  @custom:error ShuttleNotInitialized
     */
    error PillarsOfCreation__ShuttleNotInitialized();

    /**
     *  @dev Reverts if we are initializing shuttle rewards twice
     *
     *  @custom:error ShuttleAlreadyInitialized
     */
    error PillarsOfCreation__ShuttleAlreadyInitialized();

    /**
     *  @dev Reverts when the total weight is above 100% when setting lender/borrower splits
     *
     *  @custom:error InvalidTotalWeight
     */
    error PillarsOfCreation__InvalidTotalWeight();

    /**
     *  @dev Reverts when the artificer contract is enabled and the msg sender is not artificer
     *  @notice Mainly used to set/update rewards
     *
     *  @custom:error OnlyArtificer
     */
    error PillarsOfCreation__OnlyArtificer();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a new `cygPerBlock` is set manually by Admin
     *
     *  @param lastRewardRate The previous `cygPerBlock rate`
     *  @param newRewardRate The new `cygPerBlock` rate
     *
     *  @custom:event NewCygPerBlock
     */
    event NewCygPerBlock(uint256 lastRewardRate, uint256 newRewardRate);

    /**
     *  @dev Logs when a new collateral is set
     */
    event NewShuttleRewards(address borrowable, address collateral, uint256 totalAlloc, uint256 alloc);

    /**
     *  @dev Logs when a bonus rewarder is set for a shuttle
     */
    event NewBonusRewarder(address borrowable, address collateral, IBonusRewarder bonusRewarder);

    /**
     *  @dev Logs when a bonus rewarder is removed from a shuttle
     */
    event RemoveBonusRewarder(address borrowable, address collateral);

    /**
     *  @dev Logs when a lending pool is updated
     *
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param collateral Address of the CygnusCollateral contract
     *  @param sender The msg.sender
     *  @param lastRewardTime The last reward time for this pool
     *  @param epoch The current epoch
     *
     *  @custom:event UpdateShuttle
     */
    event UpdateShuttle(address indexed borrowable, address indexed collateral, address sender, uint256 lastRewardTime, uint256 epoch);

    /**
     *  @notice Logs when user collects their pending CYG from a single pool pools
     *
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param receiver The receiver of the CYG rewards
     *  @param reward CYG reward collected amount
     *
     *  @custom:event CollectCYG
     */
    event Collect(address indexed borrowable, address indexed collateral, address receiver, uint256 reward);

    /**
     *  @notice Logs when user collects their pending CYG from all pools
     *
     *  @param totalPools The total number of pools harvested
     *  @param reward The total amount of CYG collected
     */
    event CollectAll(uint256 totalPools, uint256 reward);

    /**
     *  @notice Logs when user collects their pending CYG from all specific borrow or lending pools
     *
     *  @param totalPools The total number of pools harvested
     *  @param reward The total amount of CYG collected
     *  @param borrowRewards Whether the user collected borrow or lending reward pools
     */
    event CollectAllSingle(uint256 totalPools, uint256 reward, bool borrowRewards);

    /**
     *  @dev Logs when a new Artificer Contract is set
     *
     *  @param oldArtificer The address of the old artificer contract
     *  @param newArtificer The address of the new artificer cntract
     *
     *  @custom:event NewArtificer
     */
    event NewArtificer(address oldArtificer, address newArtificer);

    /**
     *  @dev Logs when admin initializes pillars - Can only be initialized once!
     *
     *  @param birth The birth timestamp of the pillars
     *  @param death The death timestamp of the pillars (ie. when rewards have died out)
     *  @param _cygPerBlockRewards The CYG per block for borrowers/lenders at epoch 0
     *  @param _cygPerBlockDAO The CYG per block for the DAO at epoch 0
     */
    event InitializePillars(uint256 birth, uint256 death, uint256 _cygPerBlockRewards, uint256 _cygPerBlockDAO);

    /**
     *  @dev Logs when the complex rewarder tracks a lender or a borrower
     *
     *  @param borrowable The address of the borrowable asset.
     *  @param account The address of the lender or borrower
     *  @param balance The updated balance of the account
     *
     *  @custom:event TrackShuttle
     */
    event TrackRewards(address indexed borrowable, address indexed account, uint256 balance, address collateral);

    /**
     *  @dev Emitted when the contract self-destructs (can only self-destruct after the death unix timestamp)
     *
     *  @param sender msg.sender
     *  @param _birth The birth of this contract
     *  @param _death The planned death of this contract
     *  @param timestamp The current timestamp
     *
     *  @custom:event WeAreTheWormsThatCrawlOnTheBrokenWingsOfAnAngel
     */
    event Supernova(address sender, uint256 _birth, uint256 _death, uint256 timestamp);

    /**
     *  @dev Logs when we advance an epoch
     *
     *  @param previousEpoch The number of the previous epoch
     *  @param newEpoch The new epoch
     *  @param _oldCygPerBlock The old CYG per block
     *  @param _newCygPerBlock The new CYG per block
     *
     *  @custom:event NewEpoch
     */
    event NewEpoch(uint256 previousEpoch, uint256 newEpoch, uint256 _oldCygPerBlock, uint256 _newCygPerBlock);

    /**
     *  @dev Logs when the contract sweeps an ERC20 token
     *
     *  @param token The address of the ERC20 token that was swept.
     *  @param sender The address of the account that triggered the token sweep.
     *  @param amount The amount of tokens that were swept from the contract's balance.
     *  @param currentEpoch The current epoch at the time of the token sweep.
     *
     *  @custom:event SweepToken
     */
    event SweepToken(address indexed token, address indexed sender, uint256 amount, uint256 currentEpoch);

    /**
     *  @dev Logs when the allocation point of a borrowable asset in a Shuttle pool is updated.
     *
     *  @param borrowable The address of the borrowable asset whose allocation point was updated.
     *  @param collateral The address of the collateral asset whose allocation point was updated.
     *  @param oldAllocPoint The old allocation point of the borrowable asset in the Shuttle pool.
     *  @param newAllocPoint The new allocation point of the borrowable asset in the Shuttle pool.
     *
     *  @custom:event NewShuttleAllocPoint
     */
    event NewShuttleAllocPoint(address borrowable, address collateral, uint256 oldAllocPoint, uint256 newAllocPoint);

    /**
     *  @dev Logs when all pools get updated
     *
     *  @param shuttlesLength The total number of shuttles updated
     *  @param sender The msg.sender
     *  @param epoch The current epoch
     *
     *  @custom:event AccelerateTheUniverse
     */
    event AccelerateTheUniverse(uint256 shuttlesLength, address sender, uint256 epoch);

    /**
     *  @dev Logs when the doom switch is enabled by admin, cannot be turned off
     */
    event DoomSwitchSet(uint256 time, address sender, bool doomswitch);

    /**
     *  @dev Logs when CYG is dripped to the DAO reserves
     */
    event CygnusDAODrip(address receiver, uint256 amount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Mapping to keep track of PoolInfo for each borrowable asset
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @return active Whether the pool has been initialized or not (can only be set once)
     *  @return totalShares The total number of shares held in the pool
     *  @return accRewardPerShare The accumulated reward per share of the pool
     *  @return lastRewardTime The timestamp of the last reward distribution
     *  @return allocPoint The allocation points of the pool
     *  @return bonusRewarder The rewarder contract to receive bonus token rewards apart from CYG
     *  @return shuttleId The ID of the lending pool (shared by borrowable/collateral)
     *  @return pillarsId The index of the shuttle in the array
     */
    function getShuttleInfo(
        address borrowable,
        address collateral
    ) external view returns (bool, uint256, address, address, uint256, uint256, uint256, uint256, IBonusRewarder, uint256);

    /**
     *  @notice Mapping to keep track of UserInfo for each user's deposit and borrow activity
     *  @param borrowable The address of the borrowable contract.
     *  @param user The address of the user to check rewards for.
     *  @return shares The number of shares held by the user
     *  @return rewardDebt The amount of reward debt the user has accrued
     */
    function getUserInfo(address borrowable, address collateral, address user) external view returns (uint256, int256);

    /**
     *  @notice Mapping to keep track of EpochInfo for each epoch
     *  @param id The epoch number (limited by TOTAL_EPOCHS)
     *  @return epoch The ID for this epoch
     *  @return rewardRate The CYG reward rate for this epoch
     *  @return totalRewards The total amount of CYG estimated to be rewarded in this epoch
     *  @return totalClaimed The total amount of claimed CYG
     *  @return start The unix timestamp of when this epoch started
     *  @return end The unix timestamp of when it ended or is estimated to end
     */
    function getEpochInfo(
        uint256 id
    ) external view returns (uint256 epoch, uint256 rewardRate, uint256 totalRewards, uint256 totalClaimed, uint256 start, uint256 end);

    /**
     *  @return Get the total amount of pools we have initialized
     */
    function shuttlesLength() external view returns (uint256);

    /**
     *  @return SECONDS_PER_YEAR Constant variable representing the number of seconds in a year
     */
    function SECONDS_PER_YEAR() external pure returns (uint256);

    /**
     *  @return Constant variable representing the duration of the contract in seconds
     */
    function DURATION() external pure returns (uint256);

    /**
     *  @return TOTAL_EPOCHS The total number of epochs.
     */
    function TOTAL_EPOCHS() external pure returns (uint256);

    /**
     *  @return BLOCKS_PER_EPOCH The duration of each epoch.
     */
    function BLOCKS_PER_EPOCH() external pure returns (uint256);

    /**
     *  @return Human readable name for this rewarder
     */
    function name() external view returns (string memory);

    /**
     *  @return Version of the rewarder
     */
    function version() external pure returns (string memory);

    /**
     *  @return REDUCTION_FACTOR_PER_EPOCH The reduction factor per epoch (945 / 1000 = 5.5%).
     */
    function REDUCTION_FACTOR_PER_EPOCH() external pure returns (uint256);

    /**
     *  @return hangar18 Address of hangar18 in this chain
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return birth Unix timestamp representing the time of contract deployment
     */
    function birth() external view returns (uint256);

    /**
     *  @return death Unix timestamp representing the time of contract destruction
     */
    function death() external view returns (uint256);

    /**
     *  @return cygToken The address of the CYG ERC20 Token
     */
    function cygToken() external view returns (address);

    /**
     *  @return totalAllocPoint Total allocation points across all pools
     */
    function totalAllocPoint() external view returns (uint256);

    /**
     *  @return lastEpochTime The timestamp of the end of the last epoch.
     */
    function lastEpochTime() external view returns (uint256);

    /**
     *  @return totalCygClaimed Total rewards given out by this contract up to this point.
     */
    function totalCygClaimed() external view returns (uint256);

    /**
     *  @dev Calculates the emission curve for CYG emissions.
     *
     *  @param epoch The epoch we are calculating the curve for
     *  @return emissionsCurve The CYG emissions curve at `epoch`
     */
    function emissionsCurve(uint256 epoch) external pure returns (uint256);

    /**
     *  @return getBlockTimestamp The current block timestamp.
     */
    function getBlockTimestamp() external view returns (uint256);

    /**
     *  @return This function calculates the current epoch based on the current time and the contract deployment time
     *          It checks if the contract has expired and returns the total number of epochs if it has
     */
    function getCurrentEpoch() external view returns (uint256);

    /**
     *  @return currentEpochRewards The current epoch rewards for the DAO as per the emissions curve
     */
    function currentEpochRewardsDAO() external view returns (uint256);

    /**
     *  @return currentEpochRewards The current epoch rewards for borrowers/lenders as per the emissions curve
     */
    function currentEpochRewards() external view returns (uint256);

    /**
     *  @return previousEpochRewards The previous epoch rewards as per the emissions curve
     */
    function previousEpochRewards() external view returns (uint256);

    /**
     *  @return nextEpochRewards The amount of rewards to be released in the next epoch.
     */
    function nextEpochRewards() external view returns (uint256);

    /**
     *  @dev Get the time in seconds until this contract self-destructs
     */
    function untilSupernova() external view returns (uint256);

    /**
     *  @dev Calculates the amount of CYG tokens that should be emitted per block for a given epoch.
     *  @param epoch The epoch for which to calculate the emissions rate.
     *  @param totalRewards The total amount of rewards distributed by the end of total epochs
     *  @return The amount of CYG tokens to be emitted per block.
     */
    function calculateCygPerBlock(uint256 epoch, uint256 totalRewards) external view returns (uint256);

    /**
     *  @dev Calculates the total amount of CYG tokens that should be emitted during a given epoch.
     *  @param epoch The epoch for which to calculate the total emissions.
     *  @param totalRewards The total rewards given out by the end of the total epochs.
     *  @return The total amount of CYG tokens to be emitted during the epoch.
     */
    function calculateEpochRewards(uint256 epoch, uint256 totalRewards) external view returns (uint256);

    /**
     *  @return doomswitch Whether the doom which is enabled or not
     */
    function doomswitch() external view returns (bool);

    /**
     *  @return totalCygRewards The total amount of CYG tokens to be distributed to borrowers and lenders by `death` timestamp
     */
    function totalCygRewards() external view returns (uint256);

    /**
     *  @return totalCygDAO The total amount of CYG to be distributed to the DAO by the end of this contract's lifetime
     */
    function totalCygDAO() external view returns (uint256);

    /**
     *  @return cygPerBlockRewards The amount of CYG this contract gives out to per block
     */
    function cygPerBlockRewards() external view returns (uint256);

    /**
     *  @return cygPerBlockDAO The current cygPerBlock for the dao
     */
    function cygPerBlockDAO() external view returns (uint256);

    /**
     *  @return lastDripDAO The timestamp of last DAO drip
     */
    function lastDripDAO() external view returns (uint256);

    /**
     *  @return artificer The address of the artificer, capable of manipulation individual pool rewards
     */
    function artificer() external view returns (address);

    /**
     *  @return Whether or not the artificer is enabled
     */
    function artificerEnabled() external view returns (bool);

    // Simple view functions

    /**
     * @return epochProgression The current epoch progression.
     */
    function epochProgression() external view returns (uint256);

    /**
     * @return blocksThisEpoch The distance travelled in blocks this epoch.
     */
    function blocksThisEpoch() external view returns (uint256);

    /**
     *  @return epochRewardsPacing The pacing of rewards for the current epoch as a percentage
     */
    function epochRewardsPacing() external view returns (uint256);

    /**
     *  @return timeUntilNextEpoch The time left until the next epoch starts.
     */
    function untilNextEpoch() external view returns (uint256);

    /**
     * @return totalProgression The total contract progression.
     */
    function totalProgression() external view returns (uint256);

    /**
     *  @return daysUntilNextEpoch Days until this epoch ends and the next epoch begins
     */
    function daysUntilNextEpoch() external view returns (uint256);

    /**
     *  @return daysUntilSupernova The amount of days until this contract self-destructs
     */
    function daysUntilSupernova() external view returns (uint256);

    /**
     *  @return daysPassedThisEpoch How many days have passed since the star tof this epoch
     */
    function daysPassedThisEpoch() external view returns (uint256);

    /**
     *  @dev Uses the library's `timestampToDateTime` function to avoid repeating ourselves
     */
    function timestampToDateTime(
        uint256 timestamp
    ) external pure returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Uses the library's `diffDays` function to avoid repeating ourselves
     */
    function diffDays(uint256 fromTimestamp, uint256 toTimestamp) external pure returns (uint256 result);

    /**
     *  @dev Returns the datetime that this contract self destructs
     */
    function dateSupernova() external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime this epoch ends and next epoch begins
     */
    function dateNextEpochStart()
        external
        view
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev  Returns the datetime the current epoch started
     */
    function dateCurrentEpochStart()
        external
        view
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime the last epoch started
     */
    function dateLastEpochStart()
        external
        view
        returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime that `epoch` started
     *  @param epoch The epoch number to get the date time of
     */
    function dateEpochStart(
        uint256 epoch
    ) external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime that `epoch` ends
     *  @param epoch The epoch number to get the date time of
     */
    function dateEpochEnd(
        uint256 epoch
    ) external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    //  User functions  //

    /**
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the user.
     *
     *  @param borrowable The address of the Cygnus borrow contract
     *  @param account The address of the user
     *  @param borrowRewards Whether to check for pending borrow or lender rewards
     *  @return The amount of CYG tokens pending to be claimed by `account`.
     */
    function pendingCyg(address borrowable, address account, bool borrowRewards) external view returns (uint256);

    /**
     *  @notice Collects CYG rewards from all borrow or lend pools specifically.
     *  @notice Only msg.sender can collect their rewards.
     *  @param account The addres sof the user
     *  @param borrowRewards Whether to check for pending borrow or lender rewards
     *
     */
    function pendingCygSingle(address account, bool borrowRewards) external view returns (uint256 pending);

    /**
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the user for all pools.
     *
     *  @param account The address of the user.
     *  @return The amount of CYG tokens pending to be claimed by `account`.
     */
    function pendingCygAll(address account) external view returns (uint256);

    /**
     *  @dev Returns bonus rewards for a user
     *
     *  @param borrowable The address of the borrowable
     *  @param collateral The address of the collateral
     *  @param account The address of the user
     */
    function pendingBonusReward(address borrowable, address collateral, address account) external view returns (address, uint256);

    /**
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the DAO
     */
    function pendingCygDAO() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Main entry point into the Pillars. For borrowers, after taking out a loan the core contracts
     *          check for whether the pillars are set or not. If the pillars are set, then the borrowable
     *          contract passes the principal (ie the user's borrow amount) and the collateral address to this
     *          contract to track their rewards. For lenders this occurs after minting, redeeming or any transfer
     *          of CygUSD. After any transfer the borrowable checks the user's balance of CygUSD (borrowable vault
     *          token) and passes this to the Pillars along wtih to track lending rewards, using the zero address
     *          as collateral.
     *
     *          Effects:
     *            - Updates the shares and reward debt of the borrower or lender in this shuttle
     *            - Updates the total shares of the shuttle being tracked
     *
     *  @param account The address of the lender or borrower
     *  @param balance The latest balance of CygUSD (for lenders) and the borrowed principal of borrowers
     *  @param collateral The address of the collateral (this is the zero address for lenders)
     */
    function trackRewards(address account, uint256 balance, address collateral) external;

    /**
     *  @notice Main function used by borrowers or lenders to collect their CYG rewards for a specific pool.
     *  @notice Only msg.sender can collect their rewards.
     *  @param borrowable The address of the borrowable contract (CygUSD)
     *  @param to The address to which rewards are paid to
     *
     *  @custom:security non-reentrant
     */
    function collect(address borrowable, bool borrowRewards, address to) external returns (uint256 cygAmount);

    /**
     *  @notice Collects CYG rewards from all borrow or lend pools specifically.
     *  @notice Only msg.sender can collect their rewards.
     *  @param to The address to which rewards are paid to
     *  @param borrowRewards Whether user is collecting borrow rewards or lend rewards
     *
     *  @custom:security non-reentrant
     */
    function collectAllSingle(address to, bool borrowRewards) external returns (uint256 cygAmount);

    /**
     *  @notice Collects CYG rewards owed to borrowers or lenders for ALL pools in the Pillars.
     *  @notice Only msg.sender can collect their rewards.
     *  @param to The address to which rewards are paid to
     *
     *  @custom:security non-reentrant
     */
    function collectAll(address to) external returns (uint256 cygAmount);

    /**
     *  @notice Updates the reward per share for a given shuttle
     *
     *  @param borrowable The address of the borrowable contract (CygUSD)
     *  @param borrowRewards Whether the rewards we are updating are for borrowers or lenders
     *
     *  @custom:security non-reentrantoa
     */
    function updateShuttle(address borrowable, bool borrowRewards) external;

    /**
     *  @notice Updates rewards for all pools
     *
     *  @custom:security non-reentrant
     */
    function accelerateTheUniverse() external;

    /**
     *  @notice Mints Cyg to the DAO according to the `cygPerBlockDAO`
     */
    function dripCygDAO() external;

    /**
     *  @notice Self destructs the contract, stopping all CYG rewards. Reverts if we have passed TOTAL_EPOCHS
     *          and `doomswitch` is not set.
     *
     *  @custom:security non-reentrant
     */
    function supernova() external;

    /*  -------------------------------------------------------------------------------------------------------  *
     *                                           ARTIFICER FUNCTIONS 🛠️                                          *
     *  -------------------------------------------------------------------------------------------------------  */

    /**
     *  @notice Initializes CYG rewards for a specific shuttle (ie. sets lender or borrower rewards).
     *  @notice Can only be initialized once! If need to modifiy use `adjustRewards`.
     *
     *  @param borrowable The address of the borrowable contract (CygUSD)
     *  @param allocPoint The alloc point for this shuttle
     *  @param borrowRewards Whether the rewards being set are for borrowers or lenders
     *
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function setShuttleRewards(address borrowable, uint256 allocPoint, bool borrowRewards) external;

    /**
     *  @notice Adjusts CYG rewards to an already initialized shuttle (for borrowers or lender rewards)
     *
     *  @param borrowable The address of the borrowable contract (CygUSD)
     *  @param allocPoint The new alloc point for this shuttle
     *  @param borrowRewards Whether the rewards being set are for borrowers or lenders
     *
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function adjustRewards(address borrowable, uint256 allocPoint, bool borrowRewards) external;

    /**
     *  @notice Adds bonus rewards to a shuttle to reward borrowers with a bonus token (aside from CYG)
     *
     *  @param borrowable The address of the borrowable contract (CygUSD)
     *  @param borrowRewards Whether this is for lender or borrower rewards
     *  @param bonusRewarder The address of the bonus rewarder to reward users in another token other than CYG
     *
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function setBonusRewarder(address borrowable, bool borrowRewards, IBonusRewarder bonusRewarder) external;

    /**
     *  @notice Removes bonus rewards from a shuttle
     *
     *  @param borrowable The address of the borrowable
     *  @param borrowRewards Whether this is for lender or borrower rewards
     *
     *  @custom:security only-artificer-or-admin 🛠️
     */
    function removeBonusRewarder(address borrowable, bool borrowRewards) external;

    /*  -------------------------------------------------------------------------------------------------------  *
     *                                             ADMIN FUNCTIONS 👽                                            *
     *  -------------------------------------------------------------------------------------------------------  */

    /**
     *  @notice Sets the artificer, capable of adjusting rewards
     *
     *  @param _artificer The address of the new artificer contract
     *
     *  @custom:security only-admin 👽
     */
    function setArtificer(address _artificer) external;

    /**
     *  @notice Set the doom switch - Cannot be turned off!
     *
     *  @custom:security only-admin 👽
     *
     */
    function setDoomswitch() external;

    /**
     *  @notice Sweeps any erc20 token that was incorrectly sent to this contract
     *
     *  @param token The address of the token we are recovering
     *
     *  @custom:security only-admin 👽
     */
    function sweepToken(address token) external;

    /**
     *  @notice Sweeps native that was incorrectly sent to this contract
     *
     *  @custom:security only-admin 👽
     */
    function sweepNative() external;

    /*  -------------------------------------------------------------------------------------------------------  *
     *                                  INITIALIZE PILLARS - CAN ONLY BE INIT ONCE                               *
     *  -------------------------------------------------------------------------------------------------------  */

    /**
     *  @notice Initializes the contract
     *
     *  @custom:security only-admin 👽
     */
    function initializePillars() external;
}
