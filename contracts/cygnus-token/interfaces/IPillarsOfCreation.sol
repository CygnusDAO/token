// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

import {IHangar18} from "./core/IHangar18.sol";
import {IBonusRewarder} from "./IBonusRewarder.sol";

/**
 *  @notice Interface to interact with CYG rewards
 */
interface IPillarsOfCreation {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts if the cyg per block passed is above max
     *
     *  @custom:error CygPerBlockExceedsLimit
     */
    error PillarsOfCreation__CygPerBlockExceedsLimit();

    /**
     *  @dev Reverts if initializing pillars again
     *
     *  @custom:error PillarsAlreadyInitialized
     */
    error PillarsOfCreation__PillarsAlreadyInitialized();

    /**
     *  @dev Reverts when attempting to call Admin-only functions
     *
     *  @param admin The address of the admin of hangar18
     *  @param sender Address of msg.sender
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error PillarsOfCreation__MsgSenderNotAdmin(address admin, address sender);

    /**
     *  @dev Reverts if tx.origin is not msg.sender
     *
     *  @param sender The sender of the transaction
     *  @param origin The origin of the transaction
     *
     *  @custom:error OnlyAccountsAllowed
     */
    error PillarsOfCreation__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @dev Reverts if msg.sender is not a CygnusBorrow contract
     *
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param sender Address of msg.sender
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error PillarsOfCreation__MsgSenderNotBorrowable(address borrowable, address sender);

    /**
     *  @dev Reverts if pool is not initialized in the rewarder
     *
     *  @custom:error ShuttleNotInitialized
     */
    error PillarsOfCreation__ShuttleNotInitialized();

    /**
     *  @dev Reverts if borrowable is already initialized
     *
     *  @custom:error BorrowableAlreadyInitialized
     */
    error PillarsOfCreation__BorrowableAlreadyInitialized();

    /**
     *  @dev Reverts if collateral is already initialized
     *
     *  @custom:error CollateralAlreadyInitialized
     */
    error PillarsOfCreation__CollateralAlreadyInitialized();

    /**
     *  @dev Reverts when trying to sweep the underlying asset from this contract
     *
     *  @param token The address of the token we are trying to sweep
     *  @param underlying The address of CYG, which cannot be swept
     *
     *  @custom:error CantSweepUnderlying
     */
    error PillarsOfCreation__CantSweepUnderlying(address token, address underlying);

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
     *  @dev Logs when a new borrowable is set
     */
    event NewBorrowableReward(address borrowable, address collateral, uint256 totalAlloc, uint256 alloc);

    /**
     *  @dev Logs when a new collateral is set
     */
    event NewCollateralReward(address borrowable, address collateral, uint256 totalAlloc, uint256 alloc);


    /**
     *  @dev Logs when a bonus rewarder is set for a shuttle
     */
    event NewBonusRewarder(address borrowable, address collateral, IBonusRewarder bonusRewarder);

    /**
     *  @dev Logs when a lending pool is updated
     *
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param sender The msg.sender
     *  @param lastRewardTime The last reward time for this pool
     *  @param epoch The current epoch
     *
     *  @custom:event UpdateShuttle
     */
    event UpdateShuttle(address indexed borrowable, address sender, uint256 lastRewardTime, uint256 epoch);

    /**
     *  @notice Logs when `sender` harvests and receives CYG
     *
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param receiver The receiver of the CYG rewards
     *  @param reward CYG reward collected amount
     *
     *  @custom:event CollectCYG
     */
    event Collect(address indexed borrowable, address indexed collateral, address receiver, uint256 reward);

    event CollectAll(uint256 totalPools, uint256 reward);

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
     *  @dev Logs when the allocation point of a borrowable asset in a Shuttle pool is updated.
     *
     *  @param shuttleId The ID of the Shuttle pool where the allocation point was updated.
     *  @param borrowable The address of the borrowable asset whose allocation point was updated.
     *  @param oldAllocPoint The old allocation point of the borrowable asset in the Shuttle pool.
     *
     *  @custom:event RemoveShuttleReward
     */
    event RemoveShuttleReward(uint256 indexed shuttleId, address borrowable, uint256 oldAllocPoint, uint256 currentEpoch);

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
     *  @return currentEpochRewards The current epoch rewards as per the emissions curve
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
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the user.
     *
     *  @param borrowable The address of the Cygnus borrow contract.
     *  @param collateral The address of the Cygnus collateral contract.
     *  @param _user The address of the user.
     *  @return The amount of CYG tokens pending to be claimed by `_user`.
     */
    function pendingCyg(address borrowable, address collateral, address _user) external view returns (uint256);

    /**
     *  @dev Returns bonus rewards for a user
     *
     *  @param borrowable The address of the borrowable
     *  @param collateral The address of the collateral
     *  @param _user The address of the user
     */
    function pendingBonusReward(address borrowable, address collateral, address _user) external view returns (address, uint256);

    /**
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the DAO
     */
    function pendingCygDAO() external view returns (uint256);

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
     *  @return doomSwitch Whether the doom which is enabled or not
     */
    function doomSwitch() external view returns (bool);

    /**
     *  @return daoReserves The latest address of the dao reserves in the hangar18 contract
     */
    function daoReserves() external view returns (address);

    /**
     *  @return totalCygRewards The total amount of CYG tokens to be distributed to borrowers and lenders by the end of this contract's lifetime.
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
     */ // prettier-ignore
    function timestampToDateTime(uint256 timestamp) external pure returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Uses the library's `diffDays` function to avoid repeating ourselves
     */ // prettier-ignore
    function diffDays(uint256 fromTimestamp, uint256 toTimestamp) external pure returns (uint256 result);

    /**
     *  @dev Returns the datetime that this contract self destructs
     */ // prettier-ignore
    function dateSupernova() external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime this epoch ends and next epoch begins
     */ // prettier-ignore
    function dateNextEpochStart() external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev  Returns the datetime the current epoch started
     */ // prettier-ignore
    function dateCurrentEpochStart() external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime the last epoch started
     */ // prettier-ignore
    function dateLastEpochStart() external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime that `epoch` started
     *  @param epoch The epoch number to get the date time of
     */ // prettier-ignore
    function dateEpochStart( uint256 epoch) external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /**
     *  @dev Returns the datetime that `epoch` ends
     *  @param epoch The epoch number to get the date time of
     */ // prettier-ignore
    function dateEpochEnd( uint256 epoch) external view returns (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Harvests the accumulated reward for the specified user from the specified borrowable address's pool, and transfers
     *  it to the specified recipient address.
     *
     *  @param borrowable Address of the borrowable contract for which to harvest rewards.
     *  @param to Address to which to transfer the harvested rewards.
     *
     *  Effects:
     *  - Updates the user's reward debt to reflect the current accumulated reward.
     *
     *  Interactions:
     *  - Transfers the user's pending reward to the specified recipient address.
     *
     *  @custom:security non-reentrant
     */
    function collect(address borrowable, address collateral, address to) external returns (uint256 cygAmount);

    /**
     *  @dev Harvests the accumulated reward for the specified user from all initialized borrowables;
     *
     *  @param to Address to which to transfer the harvested rewards.
     *
     *  Effects:
     *  - Updates the user's reward debt to reflect the current accumulated reward.
     *
     *  Interactions:
     *  - Transfers the user's pending reward to the specified recipient address.
     *
     *  @custom:security non-reentrant
     */
    function collectAll(address to) external returns (uint256 cygAmount);

    /**
     *  @dev Tracks rewards for lenders and borrowers.
     *
     *  @param account The address of the lender or borrower
     *  @param balance The updated balance of the account
     *
     *  Effects:
     *  - Updates the shares and reward debt of the borrower in the borrowable asset's pool.
     *  - Updates the total shares of the borrowable asset's pool.
     */
    function trackRewards(address account, uint256 balance, address collateral) external;

    /**
     *  @dev Updates all the pool rewards, callable by anyone
     *
     *  @custom:security non-reentrant only-eoa
     */
    function accelerateTheUniverse() external;

    /**
     *  @notice Update the specified shuttle's reward variables to the current timestamp.
     *  @notice Updates the reward information for a specific borrowable asset. It retrieves the current
     *          ShuttleInfo for the asset, calculates the reward to be distributed based on the time elapsed
     *          since the last distribution and the pool's allocation point, updates the accumulated reward
     *          per share based on the reward distributed, and stores the updated ShuttleInfo for the asset.
     *
     *  @param borrowable The address of the borrowable asset to update.
     *
     *  @custom:security non-reentrant only-eoa
     */
    function updateShuttle(address borrowable, address collateral) external;

    /**
     *  @dev Destroys the contract and transfers remaining funds to the owner. Can only be called after 4 years from deployment.
     *
     *  @custom:security non-reentrant only-eoa
     */
    function supernova() external;

    // Admin //

    /**
     *  @notice Admin 👽
     *  @notice Initializes borrowable in the rewarder
     *
     *  @param borrowable The address of the borrowable.
     *  @param allocPoint New allocation point for the shuttle.
     *
     *  @custom:security non-reentrant only-admin
     */
    function setLendingRewards(address borrowable, uint256 allocPoint) external;

    /**
     *  @notice Admin 👽
     *  @notice Initializes collateral in the rewarder
     *
     *  @param borrowable The address of the collateral.
     *  @param collateral The address of the collateral.
     *  @param allocPoint New allocation point for the shuttle.
     *
     *  @custom:security non-reentrant only-admin
     */
    function setBorrowRewards(address borrowable, address collateral, uint256 allocPoint) external;

    /**
     *  @notice Admin 👽
     *  @notice This function is used to adjust the amount of CYG rewards that are distributed to each shuttle
     *
     *  @custom:security non-reentrant only-admin
     */
    function adjustRewards(address borrowable, address collateral, uint256 allocPoint) external;

    /**
     *  @notice Admin 👽
     *  @notice Sets a bonus rewarder to reward borrowers in a bonsu token (this is only applicable for borrowers)
     *  @param borrowable The address of the borrowable
     *  @param collateral The address of the collateral
     *  @param bonusRewarder The address of the bonus rewarder to reward users in another token other than CYG
     *  @custom:security only-admin
     */
    function setBonusRewarder(address borrowable, address collateral, IBonusRewarder bonusRewarder) external;

    /**
     *  @notice Admin 👽
     *  @notice Recovers any ERC20 token accidentally sent to this contract, sent to msg.sender
     *
     *  @param token The address of the token we are recovering
     *
     *  @custom:security only-admin
     */
    function sweepToken(address token) external;

    /**
     *  @notice Admin 👽
     *  @notice Set the doom switch on the last epoch
     *  @custom:security only-admin
     *
     */
    function setDoomSwitch() external;

    /**
     *  @notice Mints Cyg to the DAO according to the `cygPerBlockDAO`
     */
    function dripCygDAO() external;

    /**
     *  @notice Sets the artificer, capable of adjusting rewards
     */
    function setArtificer(address _artificer) external;

    /**
     *  @notice Initializes the contract
     */
    function initializePillars() external;
}
