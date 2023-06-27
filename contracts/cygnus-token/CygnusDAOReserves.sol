// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusDAOReserves} from "./interfaces/ICygnusDAOReserves.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {IHangar18} from "./interfaces/core/IHangar18.sol";

// Interfaces
import {ICygnusTerminal} from "./interfaces/core/ICygnusTerminal.sol";
import {IERC20} from "./interfaces/core/IERC20.sol";

/**
 *  @notice This contract receives all reserves and fees (if applicable) from Core contracts. 
 *          
 *          From the borrowable, this contract receives the reserve rate from borrows in the form of CygUSD. Note 
 *          that the reserves are actually kept in CygUSD instead of USD as opposed to most lending protocols. The 
 *          reserve rate is manually updatable at core contracts by admin, it is by default set to 10% with the 
 *          option to set between 0% to 20%.
 *
 *          From the collateral, this contract receives liquidation fees in the form of CygLP. The liquidation fee
 *          is also an updatable parameter by admins, and can be set anywhere between 0% and 10%. It is by default 
 *          set to 1%. This means that when CygLP is seized from the borrower, an extra 1% of CygLP is taken also.
 *
 *  @title  CygnusDAOReserves
 *  @author CygnusDAO
 *
 *                                              3.A. Harvest LP rewards
 *                   +-------------------------------------------------------------------------------+
 *                   |                                                                               |
 *                   |                                                                               ▼
 *            +------------+                         +----------------------+            +--------------------+
 *            |            |  3.B. Mint USD reserves |                      |            |                    |
 *            |    CORE    |>----------------------► |     DAO RESERVES     |>---------► |      X1 VAULT      |
 *            |            |                         |                      |            |                    |
 *            +------------+                         +----------------------+            +--------------------+
 *               ▲      |                                                                      ▲         |
 *               |      |    2. Track borrow/lend    +----------------------+                  |         |
 *               |      +--------------------------► |     CYG REWARDER     |                  |         |  6. Claim LP rewards + USDC
 *               |                                   +----------------------+                  |         |
 *               |                                            ▲    |                           |         |
 *               |                                            |    | 4. Claim CYG              |         |
 *               |                                            |    |                           |         |
 *               |                                            |    ▼                           |         |
 *               |                                   +------------------------+                |         |
 *               |    1. Deposit USDC / Liquidity    |                        |  5. Stake CYG  |         |
 *               +-----------------------------------|    LENDERS/BORROWERS   |>---------------+         |
 *                                                   |         ʕ•ᴥ•ʔ          |                          |
 *                                                   +------------------------+                          |
 *                                                              ▲                                        |
 *                                                              |                                        |
 *                                                              +----------------------------------------+
 *                                                                        LP Rewards + USDC
 *
 *       Important: Main functionality of this contract is to split the reserves received to two main addresses:
 *                  `daoReserves` and `cygnusX1Vault`
 *
 *                  This contract receives only CygUSD and CygLP (vault tokens of the Core contracts). The amount of 
 *                  assets received by the X1 Vault depends on the `x1VaultWeight` variable. Basically this contract 
 *                  redeems an amount of CygUSD shares for USDC and sends it to the vault so users can claim USD from 
 *                  reserves. The DAO receives the leftover shares which are NOT to be redeemed. These shares sit in 
 *                  the DAO reserves accruing interest (in the case of CygUSD) or earning from trading fees (in the 
 *                  case of CygLP).
 */
contract CygnusDAOReserves is ICygnusDAOReserves, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @custom:library SafeTransferLib ERC20 transfer library that gracefully handles missing return values.
    using SafeTransferLib for address;

    /// @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @inheritdoc ICygnusDAOReserves
    mapping(uint256 => Shuttle) public getShuttle;

    /// @inheritdoc ICygnusDAOReserves
    Shuttle[] public override allShuttles;

    /// @inheritdoc ICygnusDAOReserves
    uint256 public daoWeight;

    /// @inheritdoc ICygnusDAOReserves
    uint256 public override x1VaultWeight;

    /// @inheritdoc ICygnusDAOReserves
    IHangar18 public immutable override hangar18;

    /// @inheritdoc ICygnusDAOReserves
    address public immutable override usd;

    /// @inheritdoc ICygnusDAOReserves
    address public immutable override daoReserves;

    /// @inheritdoc ICygnusDAOReserves
    address public immutable override cygnusX1Vault;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @notice Constructs the DAO Reserves contract
    constructor(IHangar18 _hangar18, address _daoPositions, uint256 _weight) {
        /// @custom:error WeightNotAllowed
        if (_weight > 1e18) revert CygnusDAOReserves__WeightNotAllowed({weight: _weight});

        // Set the Hangar18 contract address
        hangar18 = _hangar18;

        // Set the positions address
        daoReserves = _daoPositions;

        // Set the CygnusX1Vault contract address
        cygnusX1Vault = _hangar18.cygnusX1Vault();

        // Set the USD contract
        usd = _hangar18.usd();

        // Set the weight of the shares that are redeemed and sent to the vault
        x1VaultWeight = _weight;

        // Set the weight of the shares that this contract receives that are sent to the dao positions address
        daoWeight = 1e18 - x1VaultWeight;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @custom:modifier cygnusAdmin Controls important parameters in both Collateral and Borrow contracts 👽
    modifier cygnusAdmin() {
        _checkAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /// @notice Internal check for msg.sender admin, checks factory's current admin 👽
    function _checkAdmin() private view {
        // Current admin from the factory
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) {
            revert CygnusDAOReserves__MsgSenderNotAdmin({admin: admin, sender: msg.sender});
        }
    }

    /// @notice Checks the `token` balance of this contract
    /// @param token The token to view balance of
    /// @return amount This contract's `token` balance
    function _checkBalance(address token) private view returns (uint256) {
        // Our balance of `token` (uses solady lib)
        return token.balanceOf(address(this));
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /// @inheritdoc ICygnusDAOReserves
    function allShuttlesLength() public view returns (uint256) {
        return allShuttles.length;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /// @notice Redeems vault token (CygUSD or CygLP)
    /// @param vaultToken The address of the CygUSD or CygLP vault token
    /// @return shares The amount of shares not redeemed
    /// @return assets The amount of assets received
    function _redeemAndFundUSD(address vaultToken) private returns (uint256 shares, uint256 assets) {
        // Get balance of vault shares we own
        uint256 totalShares = _checkBalance(vaultToken);

        // Only redeem vault shares
        uint256 x1Shares = totalShares.mulWad(x1VaultWeight);

        // Shares for the DAO
        shares = totalShares - x1Shares;

        // Assets for the X1 Vault
        if (x1Shares > 0) assets = ICygnusTerminal(vaultToken).redeem(x1Shares, cygnusX1Vault, address(this));

        // Transfer shares USD Reserves
        if (shares > 0) vaultToken.safeTransfer(daoReserves, shares);

        /// @custom:event FundX1Vault
        emit FundX1Vault(vaultToken, daoReserves, cygnusX1Vault, shares, assets);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    // USDC: Have 100 CygUSD. We redeem 50 CygUSD for USDC and send the USDC to the X1 Vault.
    //       The 50 leftover CygUSD we send to the DAO to not be redeemed, kept as reserves.

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundX1VaultUSD(uint256 shuttleId) external override nonReentrant returns (uint256 shares, uint256 assets) {
        // Address of borrowable at index `i`
        address borrowable = getShuttle[shuttleId].borrowable;

        // Redeem CygUSD for USD
        (shares, assets) = _redeemAndFundUSD(borrowable);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundX1VaultUSDAll() external override nonReentrant returns (uint256 shares, uint256 assets) {
        // Get shuttles length
        uint256 shuttlesLength = allShuttles.length;

        // Gas savings
        Shuttle[] memory _shuttles = allShuttles;

        // Loop over each lending borrowable and redeem CygUSD for USD
        for (uint256 i = 0; i < shuttlesLength; ) {
            // Address of borrowable at index `i`
            address borrowable = _shuttles[i].borrowable;

            // Redeem CygUSD for USD
            (uint256 _shares, uint256 _assets) = _redeemAndFundUSD(borrowable);

            unchecked {
                // Increase shares redeemed
                shares += _shares;

                // Increase assets received
                assets += _assets;

                // prettier-ignore
                i++;
            }
        }

        /// @custom:event FundX1VaultAll
        emit FundX1VaultAll(shuttlesLength, cygnusX1Vault, shares, assets);
    }

    // LP Tokens: Function only used if `liquidationFee` is active, meaning we receive from each Liquidation.
    //            Send 100% of the LP received to the DAO.

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundDAOPositionsCygLP(uint256 shuttleId) external override nonReentrant returns (uint256 shares) {
        // Address of borrowable at index `i`
        address collateral = getShuttle[shuttleId].collateral;

        // Get balance of vault shares we own
        shares = _checkBalance(collateral);

        // Transfer shares USD Reserves
        if (shares > 0) collateral.safeTransfer(daoReserves, shares);

        /// @custom:event FundDAOPositions
        emit FundDAOReserves(collateral, daoReserves, shares);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundDAOPositionsCygLPAll() external override nonReentrant returns (uint256 shares) {
        // Get shuttles length
        uint256 shuttlesLength = allShuttles.length;

        // Gas savings
        Shuttle[] memory _shuttles = allShuttles;

        // Loop over each lending borrowable and redeem CygUSD for USD
        for (uint256 i = 0; i < shuttlesLength; ) {
            // Address of borrowable at index `i`
            address collateral = _shuttles[i].collateral;

            // Get balance of vault shares we own
            uint256 _shares = _checkBalance(collateral);

            // Transfer shares USD Reserves
            if (_shares > 0) collateral.safeTransfer(daoReserves, _shares);

            // prettier-ignore
            unchecked { 
                // Increase shares
              shares += _shares; 

              // Next iteration
              i++;
            }
        }

        /// @custom:event FundDAOPositions
        emit FundDAOReservesAll(shuttlesLength, daoReserves, shares);
    }

    // Admin only

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant only-admin
    function setX1VaultWeight(uint256 weight) external override cygnusAdmin {
        /// @custom:error WeightNotAllowed Avoid setting new weight above 100%
        if (weight > 1e18) revert CygnusDAOReserves__WeightNotAllowed({weight: weight});

        // Old weight
        uint256 oldWeight = x1VaultWeight;

        // New weight
        x1VaultWeight = weight;

        // Adjust DAO Positions
        daoWeight = 1e18 - weight;

        /// @custom:event NewX1VaultWeight
        emit NewX1VaultWeight(oldWeight, x1VaultWeight);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant only-admin
    function addShuttle(uint256 shuttleId) external override cygnusAdmin {
        /// @custom:security ShuttleAlreadyInitialized Avoid initializing shuttle struct twice
        if (getShuttle[shuttleId].initialized) revert CygnusDAOReserves__ShuttleAlreadyInitialized({shuttleId: shuttleId});

        // Get shuttle from hangar18
        (bool launched, , address borrowable, address collateral, ) = hangar18.allShuttles(shuttleId);

        /// @custom:security ShuttleDoesntExist Avoid initializing a non-existant pool
        if (!launched) revert CygnusDAOReserves__ShuttleDoesntExist({shuttleId: shuttleId});

        // Create Lending pool with borrowable and collateral
        Shuttle memory shuttle = Shuttle({initialized: true, shuttleId: shuttleId, borrowable: borrowable, collateral: collateral});

        // Assign shuttle
        getShuttle[shuttleId] = shuttle;

        // Push to array
        allShuttles.push(shuttle);

        /// @custom:event NewShuttleAdded
        emit NewShuttleAdded(shuttle);
    }
}
