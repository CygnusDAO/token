// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// Dependencies
import {ERC20} from "./ERC20.sol";
import {ERC20Permit} from "./ERC20Permit.sol";

/// @title CygnsuERC20 The CYG token
/// @notice Admin gets total supply and distributes it to team + farm rewards
contract CygnusERC20 is ERC20Permit {
    // Constructs the CYG token
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20Permit(name_, symbol_, decimals_) {
        // Give sender total supply of CYG on this chain
        _balances[msg.sender] = totalSupply;

        /// @custom:event Transfer
        emit Transfer(address(0), msg.sender, totalSupply);
    }
}
