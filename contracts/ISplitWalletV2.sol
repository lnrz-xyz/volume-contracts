// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {SplitV2Lib} from "./SplitV2Lib.sol";

/**
 * @title Split Wallet V2
 * @author Splits
 * @notice Base splitter contract.
 * @dev `SplitProxy` handles `receive()` itself to avoid the gas cost with `DELEGATECALL`.
 */
interface ISplitWalletV2 {
    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    error UnauthorizedInitializer();
    error InvalidSplit();

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event SplitUpdated(SplitV2Lib.Split _split);
    event SplitDistributed(
        address indexed token,
        address indexed distributor,
        uint256 amount
    );

    /**
     * @notice Initializes the split wallet with a split and its corresponding data.
     * @dev Only the factory can call this function.
     * @param _split The split struct containing the split data that gets initialized.
     */
    function initialize(
        SplitV2Lib.Split calldata _split,
        address _owner
    ) external;

    /* -------------------------------------------------------------------------- */
    /*                          PUBLIC/EXTERNAL FUNCTIONS                         */
    /* -------------------------------------------------------------------------- */

    function distribute(
        SplitV2Lib.Split calldata _split,
        address _token,
        address _distributor
    ) external;

    function distribute(
        SplitV2Lib.Split calldata _split,
        address _token,
        uint256 _distributeAmount,
        bool _performWarehouseTransfer,
        address _distributor
    ) external;

    /**
     * @notice Gets the total token balance of the split wallet and the warehouse.
     * @param _token The token to get the balance of.
     * @return splitBalance The token balance in the split wallet.
     * @return warehouseBalance The token balance in the warehouse of the split wallet.
     */
    function getSplitBalance(
        address _token
    ) external view returns (uint256 splitBalance, uint256 warehouseBalance);

    /**
     * @notice Updates the split.
     * @dev Only the owner can call this function.
     * @param _split The new split struct.
     */
    function updateSplit(SplitV2Lib.Split calldata _split) external;
}
