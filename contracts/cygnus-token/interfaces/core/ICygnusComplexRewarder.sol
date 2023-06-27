//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusComplexRewarder.sol
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

/**
 *  @notice Interface for function to track user CYG rewards
 */
interface ICygnusComplexRewarder {
    /**
     *  @custom:enum Position Lending or Borrowing shuttle
     *  @custom:member LENDER If we are tracking the user's CygUSD
     *  @custom:memebr BROROWER If we are tracking the user's borrow balance
     */
    enum Position {
        LENDER,
        BORROWER
    }

    /**
     *  @dev Tracks rewards for lenders and borrowers.
     *
     *  @param account The address of the lender or borrower
     *  @param balance The updated balance of the account
     *  @param adjustmentFactor The updated borrow index of the borrowable asset or 1e18 for lenders
     *  @param position Whether the account has a borrow or lend position
     *
     *  Effects:
     *  - Updates the shares and reward debt of the borrower in the borrowable asset's pool.
     *  - Updates the total shares of the borrowable asset's pool.
     */
    function trackRewards(address account, uint256 balance, uint256 adjustmentFactor, Position position) external;
}
