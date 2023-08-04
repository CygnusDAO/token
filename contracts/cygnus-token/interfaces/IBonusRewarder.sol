// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

interface IBonusRewarder {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */
    /**
     *  @dev Reverts if msg.sender is not admin
     *  @custom:error OnlyAdmin
     */
    error BonusRewarder__OnlyAdmin();

    /**
     *  @dev Reverts if msg.sender is not pillars
     *  @custom:error OnlyPillarsOfCreation
     */
    error BonusRewarder__OnlyPillarsOfCreation();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:event OnReward Logs when it's harvested
     */
    event OnReward(address indexed borrowable, address indexed collateral, address indexed borrower, uint256 newShares, uint256 pending);

    /**
     *  @custom:event SetReward Logs when a new reward per second is set
     */
    event NewRewardPerSec(uint256 rewardPerSec);

    /**
     *  @custom:event NewBonusReward Logs when a new bonus reward is set for a shuttle
     */
    event NewBonusReward(address indexed borrowable, address indexed collateral, uint256 allocPoint);

    /**
     *  @custom:event UpdateBonusShuttle Logs when a bonus reward is updated
     */
    event UpdateBonusShuttle(
        address indexed borrowable,
        address indexed collateral,
        uint256 lastRewardTime,
        uint256 totalShares,
        uint256 accRewardPerShare
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return pillarsOfCreation The address of the Pillars of Creation contract on this chain
     */
    function pillarsOfCreation() external view returns (address);

    /**
     *  @return totalAllocPoint The total allocation points accross all pools
     */
    function totalAllocPoint() external view returns (uint256);

    /**
     *  @return rewardPerSec The rewards per sec of the bonus token
     */
    function rewardPerSec() external view returns (uint256);

    /**
     *  @return rewardToken The address of the bonus reward token
     */
    function rewardToken() external view returns (address);

    /**
     *  @return admin The address of the admin
     */
    function admin() external view returns (address);

    /**
     *  @notice View function to get the pending tokens amount
     *  @param borrowable Address of the borrowable
     *  @param collateral Address of the collateral
     *  @param user The address of the user
     */
    function pendingReward(
        address borrowable,
        address collateral,
        address user
    ) external view returns (address token, uint256 amount);

    /**
     *  @return getBlockTimestamp The latest timestamp
     */
    function getBlockTimestamp() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Harvests bonus rewards
     *  @param borrowable Address of the borrowable contract
     *  @param collateral Address of the collateral contract
     *  @param user The address of the user
     *  @param recipient The address of the bonus rewards
     *  @param rewardAmount The amount of bonus rewards harvested
     *  @param newShares The shares after harvest
     */
    function onReward(
        address borrowable,
        address collateral,
        address user,
        address recipient,
        uint256 rewardAmount,
        uint256 newShares
    ) external;

    /**
     *  @notice Sets the reward per second of rewardToken
     *  @param newReward The new reward per sec
     *  @custom:security only-admin
     */
    function setRewardPerSec(uint256 newReward) external;

    /**
     *  @notice Sets new shuttle rewards
     *  @param borrowable Address of the borrowable
     *  @param collateral Address of the collateral
     *  @param allocPoint The alloc point for this shuttle
     *  @custom:security only-admin
     */
    function initializeBonusRewards(address borrowable, address collateral, uint256 allocPoint) external;
}
