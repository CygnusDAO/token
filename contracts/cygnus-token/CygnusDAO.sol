//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusDAO.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

//  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  
//   .              .            .               .      🛰️     .           .                .           .
//          █████████     🛰️      ---======*.                                                 .           ⠀
//         ███░░░░░███                                               📡                🌔                      . 
//        ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
//       ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .           .
//       ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
//       ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
//        ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
//         ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                           .⠀
//                      ███ ░███  ███ ░███                .                 .                 .⠀
//       .             ░░██████  ░░██████        🛰️                        🛰️             .                 .     
//                      ░░░░░░    ░░░░░░      -------=========*                      .                     ⠀
//          .                            .       .          .            .                        .             .⠀
//       
//       CYGNUSDAO TOKEN ('CYG') - https://cygnusdao.finance                                                          .                     .
//  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
pragma solidity >=0.8.17;

// Dependencies
import {OFT} from "@layerzerolabs/solidity-examples/contracts/token/oft/OFT.sol";
import {ICygnusDAO} from "./interfaces/ICygnusDAO.sol";
import {IStarknetCore} from "./interfaces/IStarknetCore.sol";

/**
 *  @title  CygnusDAO CYG Token on Ethereum Mainnet.
 *  @notice On each chain the CYG token is deployed there is a cap of 5M to be minted over 6 years (156 epochs).
 *          See https://github.com/CygnusDAO/cygnus-token/blob/main/contracts/cygnus-token/PillarsOfCreation.sol
 *
 *          Instead of using `totalSupply` to cap the mints, we must keep track internally of the total minted
 *          amount, to not break compatability with the OFT's `_debitFrom` and `_creditTo` functions (since these
 *          burn and mint supply into existence respectively).
 *
 *          On Ethereum Mainnet aside from also being built as an OFT it is also integrated natively with Starknet 
 *          Core to allow sending messages between Ethereum <> Starknet, allowing to bridge CYG between the two
 *          chains instantly.
 */
contract CygnusDAO is ICygnusDAO, OFT {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @inheritdoc ICygnusDAO
     */
    uint256 public constant override CAP = 5_000_000e18;

    /**
     *  @inheritdoc ICygnusDAO
     */
    address public override pillarsOfCreation;

    /**
     *  @inheritdoc ICygnusDAO
     */
    uint256 public override totalMinted;

    //  ------------------------- 
    //          Starknet
    //  -------------------------

    /**
     *  @notice Max felt252
     *  @inheritdoc ICygnusDAO
     */
    uint256 public constant override STARKNET_MAX = 3618502788666131213697322783095070105623107215331596699973092056135872020481;

    /**
     *  @notice The L1 handler selector to teleport CYG from ethereum to starknet ('teleport_to_starknet')
     *  @inheritdoc ICygnusDAO
     */
    uint256 public constant override TELEPORT_TO_STARKNET = 0xca82aa394a9c50477a85ba3ec97709f084ea91f935210beb4332b6a67c43f4;

    /**
     *  @notice The L1 handler selector to teleport CYG from starknet to ethereum ('teleport_to_ethereum')
     *  @inheritdoc ICygnusDAO
     */
    uint256 public constant override TELEPORT_TO_ETHEREUM = 0x3d1bc017185460515029ea53aa632a4eb656e28ba51b4330645d15b6898626a;

    /**
     *  @inheritdoc ICygnusDAO
     */
    IStarknetCore public constant override STARKNET_CORE = IStarknetCore(0xc662c410C0ECf747543f5bA90660f6ABeBD9C8c4);

    /**
     *  @inheritdoc ICygnusDAO
     */
    uint256 public constant override T_T = 6370215410494176513779785366845958513491968;

    /**
     *  @inheritdoc ICygnusDAO
     */
    uint256 public override cygTokenStarknet;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the CYG OFT token and gives sender initial ownership
     */
    constructor(string memory _name, string memory _symbol, address _lzEndpoint) OFT(_name, _symbol, _lzEndpoint) {
        // Every chain deployment is the same, 250,000 inital mint rest to pillars
        uint256 initial = 250_000e18;

        // Increase initial minted
        totalMinted += initial;

        // Mint initial supply to admin
        _mint(_msgSender(), initial);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier onlyPillars Modifier for functions that can only be called by the minter contract
     */
    modifier onlyPillars() {
        _checkPillars();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Private ───────────────────────────────────────────────  */

    /**
     *  @notice Reverts if msg.sender is not CYG minter
     */
    function _checkPillars() private view {
        /// @custom:error OnlyPillars
        if (_msgSender() != pillarsOfCreation) revert OnlyPillars();
    }

    /**
     *  @notice Sanity check before bridging to l2
     */
    function _checkStarknet(uint256 recipient) private view {
        /// @custom:error InvalidL2Recipient
        if (recipient > STARKNET_MAX) revert ExceedsCairoMax();
        /// @custom:error RecipientIsZero
        else if (recipient == 0) revert RecipientIsZero();
        /// @custom:error InvalidL2Recipient
        else if (recipient == cygTokenStarknet) revert InvalidL2Recipient();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusDAO
     */
    function getL2MessageHash(address recipient, uint128 amount) external view returns (bytes32 messageHash, bool ready) {
        // The message payload
        uint256[] memory payload = new uint256[](3);

        // Recipient of CYG on Ethereum and amount
        payload[0] = T_T;
        payload[1] = uint256(uint160(recipient));
        payload[2] = amount;

        // CYG transfer message hash given recipient and amount
        messageHash = keccak256(abi.encodePacked(cygTokenStarknet, address(this), payload.length, payload));

        // Whether the message is ready to be consumed
        ready = STARKNET_CORE.l2ToL1Messages(messageHash) > 0;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    // Controls the amount of CYG to be minted on this chain

    /**
     *  @inheritdoc ICygnusDAO
     *  @custom:security only-pillars
     */
    function mint(address to, uint256 amount) external onlyPillars {
        // Gas savings
        uint256 _totalMinted = totalMinted + amount;

        /// @custom:error ExceedsSupplyCap Avoid minting above cap
        if (_totalMinted > CAP) revert ExceedsSupplyCap();

        // Increase minted amount
        totalMinted = _totalMinted;

        // Mint internally
        _mint(to, amount);
    }

    /**
     *  @inheritdoc ICygnusDAO
     *  @custom:security only-admin
     *  @custom:security only-once
     */
    function setPillarsOfCreation(address _pillars) external onlyOwner {
        // Current CYG minter
        address currentPillars = pillarsOfCreation;

        /// @custom:error PillarsAlreadySet Avoid setting the CYG minter again if already initialized
        if (currentPillars != address(0)) revert PillarsAlreadySet();

        /// @custom:event NewCYGMinter
        emit NewCYGMinter(currentPillars, pillarsOfCreation = _pillars);
    }

    //  ------------------------- 
    //          Starknet
    //  -------------------------

    /**
     *  @inheritdoc ICygnusDAO
     *  @custom:security only-admin
     *  @custom:security only-once
     */
    function setCygTokenStarknet(uint256 _cygToken) external override onlyOwner {
        // Current CYG on Starknet
        uint256 _cygTokenStarknet = cygTokenStarknet;

        /// @custom:error PillarsAlreadySet Avoid setting the CYG minter again if already initialized
        if (_cygTokenStarknet != 0) revert StarknetCygAlreadySet();

        /// @custom:event NewCYGMinter
        emit NewCYGStarknet(_cygTokenStarknet, cygTokenStarknet = _cygToken);
    }

    /**
     *  @inheritdoc ICygnusDAO
     */
    function teleportToStarknet(uint256 recipient, uint128 amount) external payable override {
        /// @custom:error CantTeleportZero
        if (amount == 0) revert CantTeleportZero();

        // Do a quick sanity check on L2 recipient
        _checkStarknet(recipient);

        // The message payload
        uint256[] memory payload = new uint256[](3);

        // Recipient of CYG on Ethereum and amount, the sum of amounts on all chains always fits in 1 slot 
        payload[0] = T_T;
        payload[1] = recipient;
        payload[2] = amount;

        // Burn first from msg.sender
        _burn(msg.sender, amount);

        // Send message to Starknet
        bytes32 messageHash = STARKNET_CORE.sendMessageToL2{value: msg.value}(cygTokenStarknet, TELEPORT_TO_STARKNET, payload);

        /// @custom:event TeleportToStarknet
        emit TeleportToStarknet(msg.sender, recipient, amount, msg.value, messageHash);
    }

    /**
     *  @inheritdoc ICygnusDAO
     */
    function teleportToEthereum(address recipient, uint128 amount) external payable override {
        /// @custom:error CantTeleportZero
        if (amount == 0) revert CantTeleportZero();

        // The message payload
        uint256[] memory payload = new uint256[](3);

        // Recipient of CYG on Ethereum and amount, the sum of amounts on all chains always fits in 1 slot 
        payload[0] = T_T;
        payload[1] = uint256(uint160(recipient));
        payload[2] = amount;

        // Consume message from L2 first, will revert if no exact message exists
        bytes32 messageHash = STARKNET_CORE.consumeMessageFromL2(cygTokenStarknet, payload);

        // Mint to msg.sender
        _mint(recipient, amount);

        // Reset teleporter for recipient
        STARKNET_CORE.sendMessageToL2{value: msg.value}(cygTokenStarknet, TELEPORT_TO_ETHEREUM, payload);

        /// @custom:event TeleportFromStarknet
        emit TeleportToEthereum(msg.sender, recipient, amount, messageHash);
    }
}
