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

/**
 *  @notice This contract receives all reserves and fees (if applicable) from Core contracts.
 *
 *          From the borrowable, this contract receives the reserve rate from borrows in the form of CygUSD. Note
 *          that the reserves are actually kept in CygUSD. The reserve rate is manually updatable at core contracts
 *          by admin, it is by default set to 10% with the option to set between 0% to 20%.
 *
 *          From the collateral, this contract receives liquidation fees in the form of CygLP. The liquidation fee
 *          is also an updatable parameter by admins, and can be set anywhere between 0% and 10%. It is by default
 *          set to 1%. This means that when CygLP is seized from the borrower, an extra 1% of CygLP is taken also.
 *
 *  @title  CygnusDAOReserves
 *  @author CygnusDAO
 *
 *                                              3.A. Harvest LP rewards
 *                   +------------------------------------------------------------------------------+
 *                   |                                                                              |
 *                   |                                                                              ▼
 *            +------------+                         +----------------------+            +--------------------+
 *            |            |  3.B. Mint USD reserves |                      |            |                    |
 *            |    CORE    |>----------------------► |     DAO RESERVES     |>---------► |      X1 VAULT      |
 *            |            |                         |   (this contract)    |            |                    |
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
    mapping(uint256 => Shuttle) public override getShuttle;

    /// @inheritdoc ICygnusDAOReserves
    Shuttle[] public override allShuttles;

    /// @inheritdoc ICygnusDAOReserves
    uint256 public override daoWeight;

    /// @inheritdoc ICygnusDAOReserves
    uint256 public override x1VaultWeight;

    /// @inheritdoc ICygnusDAOReserves
    address public override cygToken;

    /// @inheritdoc ICygnusDAOReserves
    IHangar18 public immutable override hangar18;

    /// @inheritdoc ICygnusDAOReserves
    address public immutable override usd;

    /// @inheritdoc ICygnusDAOReserves
    uint256 public override daoLock;

    /// @inheritdoc ICygnusDAOReserves
    address public override cygnusDAOSafe;

    /// @inheritdoc ICygnusDAOReserves
    address public override cygnusX1Vault;

    /// @inheritdoc ICygnusDAOReserves
    bool public override privateBanker = true;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @notice Constructs the DAO Reserves contract
    constructor(IHangar18 _hangar18, uint256 _weight) {
        /// @custom:error WeightNotAllowed
        if (_weight > 1e18) revert CygnusDAOReserves__WeightNotAllowed({weight: _weight});

        // Set the Hangar18 contract address
        hangar18 = _hangar18;

        // Set the USD contract
        usd = _hangar18.usd(); // This is underlying for all borrowables

        // Set the weight of the shares that are redeemed and sent to the vault
        x1VaultWeight = _weight;

        // Set the weight of the shares that this contract receives that are sent to the dao positions address
        daoWeight = 1e18 - x1VaultWeight;

        // CYG tokens for the DAO are locked from moving for the first 3 months
        daoLock = block.timestamp + 90 days;
    }

    /**
     *  @dev This function is called for plain Ether transfers
     */
    receive() external payable {}

    /**
     *  @dev Fallback function is executed if none of the other functions match the function identifier or no data was provided
     */
    fallback() external payable {}

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

    /// @inheritdoc ICygnusDAOReserves
    function cygTokenBalance() public view returns (uint256) {
        // If CYG token is not set
        if (cygToken == address(0)) return 0;

        // Return CYG balance
        return _checkBalance(cygToken);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /// @notice Redeems vault token (CygUSD or CygLP)
    /// @param borrowable The address of the CygUSD or CygLP vault token
    /// @return shares The amount of shares not redeemed
    /// @return assets The amount of assets received
    function _redeemAndFundUSD(address borrowable) private returns (uint256 shares, uint256 assets) {
        /// @custom:error CantRedeemAddressZero Avoid if shuttle does not exist
        if (borrowable == address(0)) revert CygnusDAOReserves__CantRedeemAddressZero();

        // Get balance of vault shares we own
        uint256 totalShares = _checkBalance(borrowable);

        // Only redeem vault shares
        uint256 x1Shares = totalShares.mulWad(x1VaultWeight);

        // Shares for the DAO
        shares = totalShares - x1Shares;

        // Assets for the X1 Vault
        if (x1Shares > 0) assets = ICygnusTerminal(borrowable).redeem(x1Shares, cygnusX1Vault, address(this));

        // Transfer shares USD Reserves
        if (shares > 0) borrowable.safeTransfer(cygnusDAOSafe, shares);
    }

    function _redeemAndFundCygLP(address collateral) private returns (uint256 shares) {
        // Get balance of this CygLP we own
        shares = _checkBalance(collateral);

        // Transfer CygLP to the safe
        if (shares > 0) collateral.safeTransfer(cygnusDAOSafe, shares);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    // USDC: Have 100 CygUSD. We redeem 50 CygUSD for USDC and send the USDC to the X1 Vault.
    //       The 50 leftover CygUSD we send to the DAO to not be redeemed, kept as reserves.

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundX1VaultUSD(uint256 shuttleId) external override nonReentrant returns (uint256 daoShares, uint256 x1Assets) {
        // If the private banker is set to "TRUE" then we revert if msg.sender is not admin
        if (privateBanker) _checkAdmin();

        // Address of borrowable at index `i`
        address borrowable = getShuttle[shuttleId].borrowable;

        // Redeem CygUSD for USD
        (daoShares, x1Assets) = _redeemAndFundUSD(borrowable);

        /// @custom:event FundX1Vault
        emit FundX1Vault(borrowable, cygnusDAOSafe, cygnusX1Vault, daoShares, x1Assets);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundX1VaultUSDAll() external override nonReentrant returns (uint256 daoShares, uint256 x1Assets) {
        // If the private banker is set to "TRUE" then we revert if msg.sender is not admin
        if (privateBanker) _checkAdmin();

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
                daoShares += _shares;

                // Increase assets received
                x1Assets += _assets;

                i++;
            }
        }

        /// @custom:event FundX1VaultAll
        emit FundX1VaultAll(shuttlesLength, cygnusX1Vault, daoShares, x1Assets);
    }

    // LP Tokens: Function only used if `liquidationFee` is active, meaning we receive from each Liquidation.

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundDAOPositionsCygLP(uint256 shuttleId) external override nonReentrant returns (uint256 daoShares) {
        // If the private banker is set to "TRUE" then we revert if msg.sender is not admin
        if (privateBanker) _checkAdmin();

        // Get this shuttle's collateral address
        address collateral = getShuttle[shuttleId].collateral;

        // Send CygLP to the safe if we have any
        daoShares = _redeemAndFundCygLP(collateral);

        /// @custom:event FundDAOCygLP
        emit FundDAOReserves(collateral, cygnusDAOSafe, daoShares);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security non-reentrant
    function fundDAOPositionsCygLPAll() external override nonReentrant returns (uint256 daoShares) {
        // If the private banker is set to "TRUE" then we revert if msg.sender is not admin
        if (privateBanker) _checkAdmin();

        // Get shuttles length
        uint256 shuttlesLength = allShuttles.length;

        // Gas savings
        Shuttle[] memory _shuttles = allShuttles;

        // Loop over each collateral and check for our CygLP balance
        for (uint256 i = 0; i < shuttlesLength; ) {
            // Get collateral for shuttle at index `i`
            address collateral = _shuttles[i].collateral;

            unchecked {
                // Send CygLP to the safe if we have any
                daoShares += _redeemAndFundCygLP(collateral);

                // Next iteration
                i++;
            }
        }

        /// @custom:event FundDAOPositions
        emit FundDAOReservesAll(shuttlesLength, cygnusDAOSafe, daoShares);
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

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security only-admin
    function setCYGToken(address _token) external override cygnusAdmin {
        // Important: Can only be set once!
        if (cygToken != address(0)) return;

        // Assign the CYG token
        cygToken = _token;

        /// @custom:event CygTokenAdded
        emit CygTokenAdded(_token);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security only-admin
    function sweepToken(address token) external override cygnusAdmin {
        // Escape if the token is CygToken OR if cygToken has not been set yet, cannot sweep
        if (token == cygToken || cygToken == address(0)) return;

        // Balance this contract has of the erc20 token we are recovering
        uint256 balance = token.balanceOf(address(this));

        // Transfer token
        token.safeTransfer(msg.sender, balance);

        /// @custom:event SweepToken
        emit SweepToken(token, balance);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security only-admin
    function claimCygTokenDAO(uint256 amount, address to) external override cygnusAdmin {
        // Current timestamp of withdrawal
        uint256 currentTime = block.timestamp;

        /// @custom:error CantClaimCygYet
        if (currentTime < daoLock) revert CygnusDAOReserves__CantClaimCygYet({time: currentTime, claimAt: daoLock});

        // Balance of CYG
        uint256 balance = cygTokenBalance();

        /// @custom:error NotEnoughCyg
        if (amount > balance) revert CygnusDAOReserves__NotEnoughCyg({amount: amount, balance: balance});

        // Transfer to `to`
        cygToken.safeTransfer(to, amount);

        /// @custom:event ClaimCygToken
        emit ClaimCygToken(amount, to);
    }

    /// @inheritdoc ICygnusDAOReserves
    /// @custom:security only-admin
    function switchPrivateBanker() external override cygnusAdmin {
        // Switch status
        privateBanker = !privateBanker;

        /// @custom:event SwitchPrivateBanker
        emit SwitchPrivateBanker(privateBanker);
    }

    function increaseDaoLock() external cygnusAdmin {}

    error CygnusDAOReserves__SafeCantBeZero();
    error CygnusDAOReserves__X1VaultCantBeZero();

    function setCygnusDAOSafe(address _newSafe) external cygnusAdmin {
        if (_newSafe == address(0)) revert CygnusDAOReserves__SafeCantBeZero();
        cygnusDAOSafe = _newSafe;
    }

    function setCygnusX1Vault(address _x1Vault) external cygnusAdmin {
        if (_x1Vault == address(0)) revert CygnusDAOReserves__X1VaultCantBeZero();
        cygnusX1Vault = _x1Vault;
    }
}
