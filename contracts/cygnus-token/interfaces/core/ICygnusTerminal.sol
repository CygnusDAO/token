//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusTerminal.sol
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
pragma solidity >=0.8.17;

// Dependencies
import {IERC20Permit} from "./IERC20Permit.sol";

/**
 *  @title ICygnusTerminal
 *  @notice The interface to mint/redeem pool tokens (CygLP and CygUSD)
 */
interface ICygnusTerminal is IERC20Permit {

    /**
     *  @notice Redeems the specified amount of `shares` for the underlying asset and transfers it to `recipient`.
     *
     *  @dev shares must be greater than 0.
     *  @dev If the function is called by someone other than `owner`, then the function will reduce the allowance
     *       granted to the caller by `shares`.
     *
     *  @param shares The number of shares to redeem for the underlying asset.
     *  @param recipient The address that will receive the underlying asset.
     *  @param owner The address that owns the shares.
     *
     *  @return assets The amount of underlying assets received by the `recipient`.
     */
    function redeem(uint256 shares, address recipient, address owner) external returns (uint256 assets);

    /**
     *  @notice Exchange Rate between the pool token and the asset
     */
    function exchangeRate() external view returns (uint256);

    /**
     *  @notice The lending pool ID (shared by borrowable/collateral)
     */
    function shuttleId() external view returns (uint256);

    /**
     *  @notice Get the collateral address from the borrowable
     */
    function collateral() external view returns (address);

    /**
     *  @notice Get the borrowable address from the collateral
     */
    function borrowable() external view returns (address);

    /**
     *  @notice Syncs the totalBalance in terms of its underlying (accrues interest in borrowable)
     */
    function sync() external;
}

