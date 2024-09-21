// SPDX-License-Identifier: MIT

interface ICurveCalculator {
    function calculateConstant(
        uint256 threshold,
        uint256 maxSupply
    ) external pure returns (uint256);

    function getBuyPrice(
        uint256 amount,
        uint256 currentSupply,
        uint256 K
    ) external pure returns (uint256);

    function getSellPrice(
        uint256 amount,
        uint256 currentSupply,
        uint256 K
    ) external pure returns (uint256);
}
