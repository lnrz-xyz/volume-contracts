// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IArtistToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function transfer(
        address _to,
        uint256 _value
    ) external returns (bool success);
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);

    function getCurveBalance(address holder) external view returns (uint256);

    function getCurveHolders() external view returns (address[] memory);

    function getTokensHeldInCurve() external view returns (uint256);

    function getCurveHoldersLength() external view returns (uint256);

    function getPrice(
        uint256 supply,
        uint256 amount
    ) external view returns (uint256);

    function getBuyPrice(uint256 amount) external view returns (uint256);

    function getSellPrice(uint256 amount) external view returns (uint256);

    function getThreshold() external view returns (uint256);

    function getVolume() external view returns (uint256);
}
