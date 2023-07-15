//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusERC20.sol
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
/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
    
           █████████                🛸         🛸                              🛸          .                    
     🛸   ███░░░░░███                                              📡                                     🌔   
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .             
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .           
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .
                       ███ ░███  ███ ░███                .                 .         🛸           ⠀             
         .    🛸*     ░░██████  ░░██████   .    🛸                     🛰️            -----=========*                 
                       ░░░░░░    ░░░░░░                                               🛸  ⠀
           .                            .       .             🛰️         .                          
    
        CYG Token - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.4;

// Dependencies
import {ERC20} from "./token/ERC20.sol";
import {Owned} from "./utils/Owned.sol";

/**
 *  @title Cygnus The CYG token
 *  @notice Capped and mintable only by owner
 */
contract Cygnus is ERC20, Owned {
    /**
     *  @custom:error ExceedsSupplyCap Reverts when minting above cap
     */
    error ExceedsSupplyCap();

    /**
     *  @notice Maximum cap of CYG
     */
    uint256 public constant CAP = 2_500_000e18;

    /**
     *  @inheritdoc ERC20
     */
    function name() public pure override(ERC20) returns (string memory) {
        return "Cygnus";
    }

    /**
     *  @inheritdoc ERC20
     */
    function symbol() public pure override(ERC20) returns (string memory) {
        return "CYG";
    }

    /**
     *  @notice Constructs the CYG token and gives sender initial ownership. Ownership will be
     *          transferred to the CygnusComplexRewarder once deployed.
     */
    constructor() Owned(msg.sender) {}

    /**
     *  @notice Mints CYG token into existence
     *  @notice Only the owner can mint, in our case it will be the CygnusComplexRewarder.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        /// @custom:error ExceedsSupplyCap
        if (totalSupply() + amount > CAP) revert ExceedsSupplyCap();

        // Mint internally
        _mint(to, amount);
    }
}
