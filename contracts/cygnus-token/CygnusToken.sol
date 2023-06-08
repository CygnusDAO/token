// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// Dependencies
import {ERC20} from "./ERC20.sol";

/// @title CygnsuERC20 The CYG token
contract CygnusERC20 is ERC20 {
    // Override name
    function name() public pure override(ERC20) returns (string memory) {
        return "CygnusDAO";
    }

    // Override symbol
    function symbol() public pure override(ERC20) returns (string memory) {
        return "CYG";
    }

    constructor() {
        // Logic to fund the ComplexRewarder goes here
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20) {
        // Override to cap supply
    }
}
