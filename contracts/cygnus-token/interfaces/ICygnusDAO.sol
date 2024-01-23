// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

// Dependencies
import {IOFT} from "@layerzerolabs/solidity-examples/contracts/token/oft/IOFT.sol";
import {IStarknetCore} from "./IStarknetCore.sol";

/**
 *  @title CygnusDAO CYG token built as layer-zero`s OFT.
 *  @notice On each chain the CYG token is deployed there is a cap of 2.5M to be minted over 42 epochs (4 years).
 *          See https://github.com/CygnusDAO/cygnus-token/blob/main/contracts/cygnus-token/PillarsOfCreation.sol
 *          Instead of using `totalSupply` to cap the mints, we must keep track internally of the total minted
 *          amount, to not break compatability with the OFT's `_debitFrom` and `_creditTo` functions (since these
 *          burn and mint supply into existence respectively).
 */
interface ICygnusDAO is IOFT {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error ExceedsSupplyCap Reverts when minting above cap
     */
    error ExceedsSupplyCap();

    /**
     *  @custom:error PillarsAlreadySet Reverts when assigning the minter contract again
     */
    error PillarsAlreadySet();

    /**
     *  @custom:error OnlyPillars Reverts when msg.sender is not the CYG minter contract
     */
    error OnlyPillars();

    /// Starknet

    /**
     *  @custom:error CantTeleportZero Reverts if bridging 0 Cyg to starknet
     */
    error CantTeleportZero();

    /**
     *  @custom:error Uint128Overflow Reverts if bridging amount exceeds uint128
     */
    error Uint128Overflow();

    /**
     *  @custom:error Reverts when L2 Recipient exceeds Cairo felt252 limit
     */
    error InvalidL2Recipient();

    /**
     *  @custom:error Reverts when setting Starknet twice
     */
    error StarknetCygAlreadySet();

    /**
     *  @custom:error Reverts if recipient is not a starknet valid address
     */
    error ExceedsCairoMax();

    /**
     *  @custom:error Reverts when Starknet recipient is zero
     */
    error RecipientIsZero();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:event NewCYGMinter Emitted when the CYG minter contract is set, only emitted once
     */
    event NewCYGMinter(address oldMinter, address newMinter);

    /**
     *  @custom:event NewCYGStarknet Emitted when CYG on Starknet is set
     */
    event NewCYGStarknet(uint256 oldCygStarknet, uint256 newCygStarknet);

    /**
     *  @custom:event TeleportToStarknet Emitted when CYG is teleported from Ethereum to Starknet
     */
    event TeleportToStarknet(address sender, uint256 recipient, uint256 amount, uint256 fee, bytes32 messageHash);

    /**
     *  @custom:event TeleportToEthereum Emitted when CYG is teleported from Starknet to Ethereum
     */
    event TeleportToEthereum(address sender, address recipient, uint256 amount, bytes32 messageHash);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Maximum cap of CYG on this chain
     */
    function CAP() external pure returns (uint256);

    /**
     *  @notice The CYG minter contract
     */
    function pillarsOfCreation() external view returns (address);

    /**
     *  @notice Stored minted amount on this chain
     */
    function totalMinted() external view returns (uint256);

    /// Starknet

    /**
     *  @notice T_T
     */
    function T_T() external pure returns (uint256);

    /**
     *  @notice Cairo Prime (2 ** 251 + 17 * 2 ** 192 + 1)
     */
    function STARKNET_MAX() external view returns (uint256);

    /**
     *  @notice Selector of the l1_handler function ('teleport_to_ethereum')
     */
    function TELEPORT_TO_ETHEREUM() external view returns (uint256);

    /**
     *  @notice Selector of the l1_handler function ('teleport_to_starknet')
     */
    function TELEPORT_TO_STARKNET() external view returns (uint256);

    /**
     *  @notice Address of starknet core
     */
    function STARKNET_CORE() external view returns (IStarknetCore);

    /**
     *  @notice Address of the CYG token on Starknet
     */
    function cygTokenStarknet() external view returns (uint256);

    /**
     *  @notice Previews the L2 message hash and whether it's ready to be consumed or not
     */
    function getL2MessageHash(address recipient, uint128 amount) external view returns (bytes32, bool);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Assigns the only contract on the chain that can mint the CYG token. Can only be set once.
     *  @param _pillars The address of the minter contract
     *  @custom:security only-admin
     *  @custom:security only-once
     */
    function setPillarsOfCreation(address _pillars) external;

    /**
     *  @notice Sets the CYG token on starknet
     *  @param _cygToken The address of the CYG token on Starknet
     *  @custom:security only-admin
     *  @custom:security only-once
     */
    function setCygTokenStarknet(uint256 _cygToken) external;

    /**
     *  @notice Mints CYG token into existence. Uses stored `totalMinted` instead of `totalSupply` as to not break
     *          compatability with lzapp's `_debitFrom` and `_creditTo` functions
     *  @notice Only the `pillarsOfCreation` contract may mint
     *  @param to The receiver of the CYG token
     *  @param amount The amount of CYG token to mint
     *  @custom:security only-pillars
     */
    function mint(address to, uint256 amount) external;

    /**
     *  @notice Teleports CYG from ETH L1 to Starknet
     *  @param recipient The recipient of CYG on Starknet
     *  @param amount The amount of CYG being teleported to Starknet
     */
    function teleportToStarknet(uint256 recipient, uint128 amount) external payable;

    /**
     *  @notice Teleports CYG from Starknet to ETH mainnet
     *  @param recipient The recipient of CYG on Ethereum
     *  @param amount The amount of CYG being teleported from Starknet
     */
    function teleportToEthereum(address recipient, uint128 amount) external payable;
}
