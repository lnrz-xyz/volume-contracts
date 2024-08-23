// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import {SplitV2Lib} from "./SplitV2Lib.sol";
interface ISplitFactoryV2 {
    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event SplitCreated(
        address indexed split,
        SplitV2Lib.Split splitParams,
        address owner,
        address creator
    );

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Create a new split using create2.
     * @param _splitParams Params to create split with.
     * @param _owner Owner of created split.
     * @param _creator Creator of created split.
     * @param _salt Salt for create2.
     */
    function createSplitDeterministic(
        SplitV2Lib.Split calldata _splitParams,
        address _owner,
        address _creator,
        bytes32 _salt
    ) external returns (address split);

    /**
     * @notice Create a new split with params and owner.
     * @dev Uses a hash-based incrementing nonce over params and owner.
     * @param _splitParams Params to create split with.
     * @param _owner Owner of created split.
     * @param _creator Creator of created split.
     */
    function createSplit(
        SplitV2Lib.Split calldata _splitParams,
        address _owner,
        address _creator
    ) external returns (address split);

    /**
     * @notice Predict the address of a new split based on split params, owner, and salt.
     * @param _splitParams Params to create split with
     * @param _owner Owner of created split
     * @param _salt Salt for create2
     */
    function predictDeterministicAddress(
        SplitV2Lib.Split calldata _splitParams,
        address _owner,
        bytes32 _salt
    ) external view returns (address);

    /**
     * @notice Predict the address of a new split based on the nonce of the hash of the params and owner.
     * @param _splitParams Params to create split with.
     * @param _owner Owner of created split.
     */
    function predictDeterministicAddress(
        SplitV2Lib.Split calldata _splitParams,
        address _owner
    ) external view returns (address);

    /**
     * @notice Predict the address of a new split and check if it is deployed.
     * @param _splitParams Params to create split with.
     * @param _owner Owner of created split.
     * @param _salt Salt for create2.
     */
    function isDeployed(
        SplitV2Lib.Split calldata _splitParams,
        address _owner,
        bytes32 _salt
    ) external view returns (address split, bool exists);
}
