// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

import {IHangar18} from "./core/IHangar18.sol";

interface ICygnusDAOReserves {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @dev Reverts when attempting to call Admin-only functions
    /// @param admin The address of the admin of hangar18
    /// @param sender Address of msg.sender
    /// @custom:error MsgSenderNotAdmin
    error CygnusDAOReserves__MsgSenderNotAdmin(address admin, address sender);

    /// @dev Reverts when adding new shuttle to the reserves
    /// @param shuttleId The ID for the lending pool we are initializing
    /// @custom:error ShuttleNotInitialized
    error CygnusDAOReserves__ShuttleDoesntExist(uint256 shuttleId);

    /// @dev Reverts when adding new shuttle to the reserves
    /// @param shuttleId The ID for the lending pool we are initializing
    /// @custom:error ShuttleAlreadyInitialized
    error CygnusDAOReserves__ShuttleAlreadyInitialized(uint256 shuttleId);

    /// @dev Reverts when setting a new weight outside range allowed
    /// @param weight The weight of the X1 Vault
    /// @custom:error WeightNotAllowed
    error CygnusDAOReserves__WeightNotAllowed(uint256 weight);

    /// @dev Reverts when trying to claim cyg before lock period ends
    error CygnusDAOReserves__CantClaimCygYet(uint256 time, uint256 claimAt);

    /// @dev Reverts when theres not enough cyg to claim
    error CygnusDAOReserves__NotEnoughCyg(uint256 amount, uint256 balance);

    /// @dev Reverts if borrowable is not set
    error CygnusDAOReserves__CantRedeemAddressZero();

    /// @dev Reverts if Safe is 0
    error CygnusDAOReserves__SafeCantBeZero();

    /// @dev Reverts if X1 vault is 0
    error CygnusDAOReserves__X1VaultCantBeZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @dev Logs when the X1 Vault is funded with assets
    /// @param vaultToken The address of the vault token
    /// @param positions The address receiving the left over shares
    /// @param vault The address receiving the assets
    /// @param shares The amount of shares being redeemed
    /// @param assets The amount of assets funded to
    /// @custom:event FundX1Vault
    event FundX1Vault(address indexed vaultToken, address indexed positions, address indexed vault, uint256 shares, uint256 assets);

    /// @dev Logs when the DAO Positions receives CygLP
    /// @param vaultToken The address of the vault token
    /// @param positions The address of the DAO Positions
    /// @param shares The amount of shares transfered to DAO Positions
    /// @custom:event FundDAOPositions
    event FundDAOReserves(address indexed vaultToken, address indexed positions, uint256 shares);

    /// @dev Logs when admin sets a new weight for the vault
    /// @param oldWeight The old X1 Vault weight
    /// @param newWeight The new X1 Vault weight
    /// @custom:event NewX1VaultWeight
    event NewX1VaultWeight(uint256 oldWeight, uint256 newWeight);

    /// @dev Logs when a new shuttle is added
    /// @param shuttle The Shuttle struct record
    /// @custom:event NewShuttleAdded
    event NewShuttleAdded(Shuttle shuttle);

    /// @dev Logs When the Cygnus X1 Vault is funded by all shuttles
    /// @param totalShuttles The amount of lending pools we harvested
    /// @param vault The address of the X1 Vault
    /// @param shares The amount of CygUSD redeemed
    /// @param assets The amount of assets received
    /// @custom:event FundX1VaultAll
    event FundX1VaultAll(uint256 totalShuttles, address vault, uint256 shares, uint256 assets);

    /// @dev Logs When the Cygnus X1 Vault is funded by all shuttles
    /// @param totalShuttles The amount of lending pools we harvested
    /// @param positions The address of the DAO Positions
    /// @param shares The amount of shares transfered to DAO Positions
    /// @custom:event FundDAOReservesAll
    event FundDAOReservesAll(uint256 totalShuttles, address positions, uint256 shares);

    /// @dev Logs when permissions for splitting shares and assets are switched
    /// @param _privateBanker Whether only admin can split or anyone can (true = only admin)
    /// @custom:event SwitchPrivateBanker
    event SwitchPrivateBanker(bool _privateBanker);

    /// @dev Logs when the DAO claims their shares of CYG token
    /// @param amount Amount claimed of CYG token
    /// @param to Address who received the CYG tokens
    /// @custom:event ClaimCygToken
    event ClaimCygToken(uint256 amount, address to);

    /// @dev Logs when admin sweeps a token (throws is the token is CYG)
    /// @param token The address of the token
    /// @param balance The balance of the token claimed
    /// @custom:event SweepToken
    event SweepToken(address token, uint256 balance);

    /// @dev Logs when admin adds the CYG token
    /// @param token The address of the CYG token
    /// @custom:event CygTokenAdded
    event CygTokenAdded(address token);

    /// @dev Logs when admin replaces the dao safe
    /// @param oldSafe the address of the safe up to now
    /// @param newSafe the address of the new safe
    /// @custom:event NewDAOSafe
    event NewDAOSafe(address oldSafe, address newSafe);

    /// @dev Logs when admin replaces the X1 Vault
    /// @param oldVault the address of the X1 Vault up to now
    /// @param newVault the address of the new X1 Vault
    /// @custom:event NewX1Vault
    event NewX1Vault(address oldVault, address newVault);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @notice The shuttle struct for each lending pool
    /// @custom:struct Shuttle Information of each lending pool
    /// @custom:member initialized Whether the shuttle is initialized or not
    /// @custom:member shuttleId The unique identifier of the shuttle
    /// @custom:member borrowable The address of the borrowable asset
    /// @custom:member collateral The address of the collateral asset
    struct Shuttle {
        bool initialized;
        uint256 shuttleId;
        address borrowable;
        address collateral;
    }

    /// @dev Retrieves information about a specific shuttle.
    /// @param _shuttleId The ID of the shuttle to retrieve information about.
    /// @return initialized Whether the shuttle is initialized or not.
    /// @return shuttleId The unique identifier of the shuttle.
    /// @return borrowable The address of the borrowable asset.
    /// @return collateral The address of the collateral asset.
    function allShuttles(
        uint256 _shuttleId
    ) external view returns (bool initialized, uint256 shuttleId, address borrowable, address collateral);

    /// @dev Retrieves the actual shuttle ID (in case array differs)
    /// @param id The shuttle ID
    /// @return initialized Whether the shuttle is initialized or not.
    /// @return shuttleId The unique identifier of the shuttle.
    /// @return borrowable The address of the borrowable asset.
    /// @return collateral The address of the collateral asset.
    function getShuttle(uint256 id) external view returns (bool initialized, uint256 shuttleId, address borrowable, address collateral);

    /// @dev Name of the contract
    function name() external view returns (string memory);

    /// @dev Retrieves the address of the Hangar18 contract.
    /// @return The address of the Hangar18 contract.
    function hangar18() external view returns (IHangar18);

    /// @dev Retrieves the address of the Cygnus DAO positions.
    /// @return The address of the CygnusDAO positions.
    function cygnusDAOSafe() external view returns (address);

    /// @dev Retrieves the address of the CygnusX1Vault contract.
    /// @return The address of the CygnusX1Vault contract.
    function cygnusX1Vault() external view returns (address);

    /// @dev Retrieves the address of the USD contract.
    /// @return The address of the USD contract.
    function usd() external view returns (address);

    /// @dev Retrieves the weight of the X1 vault.
    /// @return The weight of the X1 vault.
    function x1VaultWeight() external view returns (uint256);

    /// @dev Retrieves the weight of the DAO positions
    /// @return The weight of the DAO positions.
    function daoWeight() external view returns (uint256);

    /// @dev Retrieves the length of the allShuttles array.
    /// @return The length of the allShuttles array.
    function allShuttlesLength() external view returns (uint256);

    /// @dev Address of the CYG token
    function cygToken() external view returns (address);

    /// @dev current balance of CYg
    function cygTokenBalance() external view returns (uint256);

    /// @dev The unlock cyg DAO time
    function daoLock() external view returns (uint256);

    /// @dev Whether anyone can split shares and assets
    function privateBanker() external view returns (bool);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @dev Funds the CygnusX1Vault with all the available USD tokens from `shuttleId`
    /// @param shuttleId The ID of the lending pool
    /// @return shares The total amount of shares transferred to CygnusDAOPositions.
    /// @return assets The total amount of assets transferred to CygnusX1Vault.
    function fundX1VaultUSD(uint256 shuttleId) external returns (uint256 shares, uint256 assets);

    /// @dev Funds the CygnusX1Vault with all the available LP tokens from `shuttleId`
    /// @param shuttleId The ID of the lending pool
    /// @return shares The total amount of shares transfered to CygnusDAOPositions
    function fundDAOPositionsCygLP(uint256 shuttleId) external returns (uint256 shares);

    /// @dev Funds the CygnusX1Vault with all the available tokens from all shuttles.
    /// @return shares The total amount of shares transferred to CygnusDAOPositions.
    /// @return assets The total amount of assets transferred to CygnusX1Vault.
    function fundX1VaultUSDAll() external returns (uint256 shares, uint256 assets);

    /// @dev Funds the DAO Positions with all the available tokens from all shuttles.
    /// @return shares The total amount of shares transferred to CygnusDAOPositions.
    function fundDAOPositionsCygLPAll() external returns (uint256 shares);

    /// @dev Sets the weight of the X1 vault.
    /// @param weight The new weight to be set for the X1 vault.
    function setX1VaultWeight(uint256 weight) external;

    /// @notice Adds a shuttle to the record
    /// @param shuttleId The ID for the shuttle we are adding
    /// @custom:security non-reentrant only-admin
    function addShuttle(uint256 shuttleId) external;

    /// @notice Sweeps any token sent to this contract except the CYG token
    /// @param token The address of the token being swept
    function sweepToken(address token) external;

    /// @notice Sends an amount of `cygToken` to `to`
    function claimCygTokenDAO(uint256 amount, address to) external;

    /// @notice Sets the CYG token
    function setCYGToken(address _token) external;

    /// @notice Admin allows anyone to split the shares/assets between the DAO Reserves and X1 Vault
    /// @custom:security only-admin
    function switchPrivateBanker() external;

    /// @notice Admin assigns new safe address
    /// @custom:security only-admin
    function setCygnusDAOSafe(address _safe) external;

    /// @notice Admin assigns new X1 vault address
    /// @custom:security only-admin
    function setCygnusX1Vault(address _vault) external;

    /// @notice Sweep ETH
    function sweepNative() external;
}
