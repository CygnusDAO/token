// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import {IHangar18} from "./core/IHangar18.sol";

interface ICygnusComplexRewarder {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Reverts if the cyg per block passed is above max
     *  @param max The maximum cyg per block allowed
     *  @param value The value passed
     *  @custom:error CygPerBlockExceedsLimit
     */
    error CygnusComplexRewarder__CygPerBlockExceedsLimit(uint256 max, uint256 value);

    /**
     *  @notice Reverts when attempting to call Admin-only functions
     *  @param admin The address of the admin of hangar18
     *  @param sender Address of msg.sender
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusComplexRewarder__MsgSenderNotAdmin(address admin, address sender);

    /**
     *  @dev tx.origin must equal msg.sender
     *  @param sender The sender of the transaction
     *  @param origin The origin of the transaction
     *  @custom:error OnlyAccountsAllowed Reverts when the transaction origin and sender are different
     */
    error CygnusComplexRewarder__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @notice Reverts if msg.sender is not a CygnusBorrow contract
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param sender Address of msg.sender
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusComplexRewarder__MsgSenderNotBorrowable(address borrowable, address sender);

    /**
     *  @notice Reverts if borrowable is not initialized in the rewarder
     *  @param shuttleId The ID of this lending pool
     *  @param borrowable The address of the CygnusBorrow contract
     *  @custom:error ShuttleNotInitialized
     */
    error CygnusComplexRewarder__ShuttleNotInitialized(uint256 shuttleId, address borrowable);

    /**
     *  @notice Reverts if borrowable is already initialized
     *  @param shuttleId The ID of this lending pool
     *  @param borrowable The address of the CygnusBorrow contract
     *  @custom:error ShuttleAlreadyInitialized
     */
    error CygnusComplexRewarder__ShuttleAlreadyInitialized(uint256 shuttleId, address borrowable);

    /**
     *  @custom:error CantSweepUnderlying Reverts when trying to sweep the underlying asset from this contract
     *  @param token The address of the token we are trying to sweep
     *  @param underlying The address of CYG, which cannot be swept
     *  @custom:error CantSweepUnderlying
     */
    error CygnusComplexRewarder__CantSweepUnderlying(address token, address underlying);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when a new `cygPerBlock` is set
     *  @param lastRewardRate The previous `cygPerBlock rate`
     *  @param newRewardRate The new `cygPerBlock` rate
     *  @custom:event NewCygPerBlock
     */
    event NewCygPerBlock(uint256 lastRewardRate, uint256 newRewardRate);

    /**
     *  @notice Logs when we add a new lending pool to the rewarder
     *  @param shuttleId The `shuttleId` of the borrowable
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param allocPoints The alloc points
     *  @custom:event NewShuttleReward
     */
    event NewShuttleReward(uint256 indexed shuttleId, address indexed borrowable, uint256 allocPoints);

    /**
     *  @notice Logs when a lending pool is updated
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param lastRewardTime The last reward time for this pool
     *  @param totalShares The pool's total shares
     *  @param accRewardPerShare The accumulated reward per share based on the reward distributed
     *  @custom:event UpdateRift
     */
    event UpdateShuttle(
        address indexed borrowable,
        uint256 lastRewardTime,
        uint256 totalShares,
        uint256 accRewardPerShare
    );

    /**
     *  @notice Legs when `sender` harvests and receives CYG
     *  @param borrowable Address of the CygnusBorrow contract
     *  @param sender msg.sender
     *  @param reward CYG reward collected
     *  @custom:event CollectReward
     */
    event CollectReward(address indexed borrowable, address sender, uint256 reward);

    /**
     *  @dev Emitted when a borrower's borrow balance and borrow index are tracked.
     *  @param borrowable The address of the borrowable asset.
     *  @param borrower The address of the borrower.
     *  @param borrowBalance The updated borrow balance of the borrower.
     *  @param borrowIndex The updated borrow index of the borrowable asset.
     *  @custom:event TrackShuttle
     */
    event TrackShuttle(address indexed borrowable, address indexed borrower, uint256 borrowBalance, uint256 borrowIndex);

    /**
     *  @dev Emitted when the contract self-destructs (can only self-destruct after the death unix timestamp)
     *  @param sender msg.sender
     *  @param _birth The birth of this contract
     *  @param _death The planned death of this contract
     *  @param timestamp The current timestamp
     *  @custom:event WeAreTheWormsThatCrawlOnTheBrokenWingsOfAnAngel
     */
    event Supernova(address sender, uint256 _birth, uint256 _death, uint256 timestamp);

    /**
     *  @dev Emitted when we advance an epoch
     *  @param previousEpoch The number of the previous epoch
     *  @param newEpoch The new epoch
     *  @param _oldCygPerBlock The old CYG per block
     *  @param _newCygPerBlock The new CYG per block
     *  @custom:event NewEpoch
     */
    event NewEpoch(uint256 previousEpoch, uint256 newEpoch, uint256 _oldCygPerBlock, uint256 _newCygPerBlock);

    /**
     *  @dev Emitted when the contract sweeps an ERC20 token
     *  @param token The address of the ERC20 token that was swept.
     *  @param sender The address of the account that triggered the token sweep.
     *  @param amount The amount of tokens that were swept from the contract's balance.
     *  @param currentEpoch The current epoch at the time of the token sweep.
     *  @custom:event SweepToken
     */
    event SweepToken(address indexed token, address indexed sender, uint256 amount, uint256 currentEpoch);

    /**
     *  @dev Emitted when the allocation point of a borrowable asset in a Shuttle pool is updated.
     *  @param shuttleId The ID of the Shuttle pool where the allocation point was updated.
     *  @param borrowable The address of the borrowable asset whose allocation point was updated.
     *  @param oldAllocPoint The old allocation point of the borrowable asset in the Shuttle pool.
     *  @param newAllocPoint The new allocation point of the borrowable asset in the Shuttle pool.
     *  @custom:event NewShuttleAllocPoint
     */
    event NewShuttleAllocPoint(
        uint256 indexed shuttleId,
        address borrowable,
        uint256 oldAllocPoint,
        uint256 newAllocPoint
    );

    /**
     *  @dev Emitted when the allocation point of a borrowable asset in a Shuttle pool is updated.
     *  @param shuttleId The ID of the Shuttle pool where the allocation point was updated.
     *  @param borrowable The address of the borrowable asset whose allocation point was updated.
     *  @param oldAllocPoint The old allocation point of the borrowable asset in the Shuttle pool.
     *  @custom:event RemoveShuttleReward
     */
    event RemoveShuttleReward(
        uint256 indexed shuttleId,
        address borrowable,
        uint256 oldAllocPoint,
        uint256 currentEpoch
    );

    /**
     *  @dev Logs when all pools get updated
     *  @param shuttlesLength The total number of shuttles updated
     *  @param sender The msg.sender
     *  @param epoch The current epoch
     *  @custom:event AccelerateTheUniverse
     */
    event AccelerateTheUniverse(uint256 shuttlesLength, address sender, uint256 epoch);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Mapping to keep track of PoolInfo for each borrowable asset
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @return active Whether the pool has been initialized or not (can only be set once)
     *  @return shuttleId The ID for this shuttle to identify in hangar18
     *  @return totalShares The total number of shares held in the pool
     *  @return accRewardPerShare The accumulated reward per share of the pool
     *  @return lastRewardTime The timestamp of the last reward distribution
     *  @return allocPoint The allocation points of the pool
     */
    function getShuttleInfo(
        address borrowable
    ) external view returns (bool, uint256, uint256, uint256, uint256, uint256);

    /**
     *  @notice Mapping to keep track of UserInfo for each user's deposit and borrow activity
     *  @param borrowable The address of the borrowable contract.
     *  @param user The address of the user to check rewards for.
     *  @return shares The number of shares held by the user
     *  @return rewardDebt The amount of reward debt the user has accrued
     */
    function getUserInfo(address borrowable, address user) external view returns (uint256, int256);

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
    )
        external
        view
        returns (
            uint256 epoch,
            uint256 rewardRate,
            uint256 totalRewards,
            uint256 totalClaimed,
            uint256 start,
            uint256 end
        );

    /**
     *  @notice Get the total amount of pools we have initialized
     */
    function shuttlesLength() external view returns (uint256);

    /**
     *  @return ACC_PRECISION Constant used for precision calculations
     */
    function ACC_PRECISION() external pure returns (uint256);

    /**
     *  @return SHARES_PRECISION is a constant used for precision calculations
     */
    function SHARES_PRECISION() external pure returns (uint256);

    /**
     *  @return MAX_CYG_PER_BLOCK The maximum amount of CYG per block this contract can give to users
     */
    function MAX_CYG_PER_BLOCK() external pure returns (uint256);

    /**
     *  @return BLOCKS_PER_YEAR Constant variable representing the number of blocks in a year
     */
    function BLOCKS_PER_YEAR() external pure returns (uint256);

    /**
     *  @notice Constant variable representing the duration of the contract in seconds
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
     *  @return cygPerBlock The amount of CYG this contract gives out to per block
     */
    function cygPerBlock() external view returns (uint256);

    /**
     *  @return totalAllocPoint Total allocation points across all pools
     */
    function totalAllocPoint() external view returns (uint256);

    /**
     *  @return lastEpochTime The timestamp of the end of the last epoch.
     */
    function lastEpochTime() external view returns (uint256);

    /**
     *  @return totalCygRewards The total amount of CYG tokens to be distributed by the end of this contract's lifetime.
     */
    function totalCygRewards() external view returns (uint256);

    /**
     *  @return totalCygClaimed Total rewards given out by this contract up to this point.
     */
    function totalCygClaimed() external view returns (uint256);

    /**
     *  @dev Calculates the emission curve for CYG emissions.
     *  @param epoch The epoch we are calculating the curve for
     *  @return The CYG emission curve.
     */
    function emissionsCurve(uint256 epoch) external pure returns (uint256);

    /**
     *  @return getBlockTimestamp The current block timestamp.
     */
    function getBlockTimestamp() external view returns (uint256);

    /**
     *  @notice This function calculates the current epoch based on the current time and the contract deployment time
     *          It checks if the contract has expired and returns the total number of epochs if it has
     */
    function getCurrentEpoch() external view returns (uint256);

    /**
     *  @return currentEpochRewards The current epoch rewards.
     */
    function currentEpochRewards() external view returns (uint256);

    /**
     *  @dev Returns the amount of CYG tokens that are pending to be claimed by the user.
     *  @param borrowable The address of the Cygnus borrow contract.
     *  @param _user The address of the user.
     *  @return The amount of CYG tokens pending to be claimed.
     */
    function pendingCyg(address borrowable, address _user) external view returns (uint256);

    /**
     *  @dev Get the time in seconds until this contract self-destructs
     */
    function distanceUntilSupernova() external view returns (uint256);

    /**
     *  @dev Array of all pools earning rewards
     */
    function allShuttles(uint256) external view returns (address);

    /**
     *  @dev Calculates the amount of CYG tokens that should be emitted per block for a given epoch.
     *  @param epoch The epoch for which to calculate the emissions rate.
     *  @return The amount of CYG tokens to be emitted per block.
     */
    function calculateCygPerBlock(uint256 epoch) external view returns (uint256);

    /**
     *  @dev Calculates the total amount of CYG tokens that should be emitted during a given epoch.
     *  @param epoch The epoch for which to calculate the total emissions.
     *  @return The total amount of CYG tokens to be emitted during the epoch.
     */
    function calculateEpochRewards(uint256 epoch) external view returns (uint256);

    // Simple view functions

    /**
     * @return epochProgression The current epoch progression.
     */
    function epochProgression() external view returns (uint256);

    /**
     * @return totalProgression The total contract progression.
     */
    function totalProgression() external view returns (uint256);

    /**
     * @return distanceThisEpoch The distance travelled in blocks this epoch.
     */
    function distanceThisEpoch() external view returns (uint256);

    /**
     * @return timeUntilNextEpoch The time left until the next epoch starts.
     */
    function distanceUntilNextEpoch() external view returns (uint256);

    /**
     * @return nextEpochRewards The amount of rewards to be released in the next epoch.
     */
    function nextEpochRewards() external view returns (uint256);

    /**
     * Returns the pacing of rewards for the current epoch.
     */
    function epochRewardsPacing() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Harvests the accumulated reward for the specified user from the specified borrowable address's pool, and transfers
     *  it to the specified recipient address.
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
    function collect(address borrowable, address to) external;

    /**
     *  @dev Tracks the borrow activity of a borrower in a specific borrowable asset.
     *  @param shuttleId The ID of the shuttle.
     *  @param borrower The address of the borrower.
     *  @param borrowBalance The current borrow balance of the borrower.
     *  @param borrowIndex The current borrow index of the borrowable asset.
     *
     *  Effects:
     *  - Updates the shares and reward debt of the borrower in the borrowable asset's pool.
     *  - Updates the total shares of the borrowable asset's pool.
     *
     *  @custom:security non-reentrant
     */
    function trackBorrower(uint256 shuttleId, address borrower, uint borrowBalance, uint borrowIndex) external;

    /**
     *  @notice Initializes lending pool in the rewarder
     *  @dev Sets the allocation point for a specific shuttle. The allocation point determines the proportion of rewards that
     *       will be distributed to this shuttle's pool relative to the others. Only hangar Admin
     *  can call this function.
     *  @param shuttleId ID of the shuttle to set the allocation point for.
     *  @param allocPoint New allocation point for the shuttle.
     *  @custom:security non-reentrant only-admin 👽
     */
    function initializeShuttleRewards(uint256 shuttleId, uint256 allocPoint) external;

    /**
     *  @notice This function is used to adjust the amount of CYG rewards that are distributed to each shuttle
     *  @param shuttleId The ID of the shuttle to adjust the allocation points for.
     *  @param allocPoint The new allocation points for the shuttle.
     *  @custom:security non-reentrant only-admin 👽
     */
    function adjustShuttleRewards(uint256 shuttleId, uint256 allocPoint) external;

    /**
     *  @dev Updates all the pool rewards, callable by anyone
     *  @custom:security non-reentrant
     */
    function accelerateTheUniverse() external;

    /**
     *  @notice Update the specified shuttle's reward variables to the current timestamp.
     *  @notice Updates the reward information for a specific borrowable asset. It retrieves the current 
     *          ShuttleInfo for the asset, calculates the reward to be distributed based on the time elapsed 
     *          since the last distribution and the pool's allocation point, updates the accumulated reward 
     *          per share based on the reward distributed, and stores the updated ShuttleInfo for the asset.
     *  @param borrowable The address of the borrowable asset to update.
     *  @custom:security non-reentrant
     */
    function updateShuttle(address borrowable) external;

    /**
     *  @dev Advances the epoch for CYG emissions.
     *  @custom:security non-reentrant
     */
    function advanceEpoch() external;

    /**
     *  @notice Updates the `cygPerBlock`
     *  @param _cygPerBlock The new `cygPerBLock`
     *  @custom:security non-reentrant only-admin 👽
     */
    function setCygPerBlock(uint256 _cygPerBlock) external;

    /**
     *  @dev Destroys the contract and transfers remaining funds to the owner. Can only be called after 4 years from deployment.
     *  @custom:security non-reentrant
     */
    function supernova() external;

    /**
     *  @notice Admin 👽
     *  @notice Recovers any ERC20 token accidentally sent to this contract, sent to msg.sender
     *  @param token The address of the token we are recovering
     *  @custom:security non-reentrant only-admin 👽
     */
    function sweepToken(address token) external;

    function name() external returns (string memory);
    function version() external returns (string memory);
}
