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
pragma solidity >=0.8.4;

// Dependencies
import {ERC20} from "./token/ERC20.sol";
import {Ownable} from "./utils/Ownable.sol";

/**
 *  @title CygnsuERC20 The CYG token
 *  @notice Capped and mintable only by owner
 */
contract CygnusERC20 is ERC20, Ownable {
    /**
     *  @custom:error ExceedsSupplyCap Reverts when minting above cap
     */
    error ExceedsSupplyCap();

    /**
     *  @notice Maximum cap of CYG
     */
    uint256 public constant CAP = 2_000_000e18;

    /**
     *  @inheritdoc ERC20
     */
    function name() public pure override(ERC20) returns (string memory) {
        return "CygnusDAO";
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
    constructor() {
        // Set initial owner
        _initializeOwner(msg.sender);
    }

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
