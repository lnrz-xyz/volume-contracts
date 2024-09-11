// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./IWETH9.sol";
import "./INonfungiblePositionManager.sol";
import "./ISplitFactoryV2.sol";
import "./ISplitWalletV2.sol";

contract VolumeConfiguration is Ownable {
    uint256 public buyFeePercent;
    uint256 public graduationFeePercent;
    uint256 public protocolFeePercent;
    uint256 public creatorFeePercent;
    uint256 public marketStatsPrice;
    uint24 public poolFeePercent;
    uint256 public liquidityPoolVolumeThreshold;

    // Uniswap and other external addresses
    IUniswapV3Factory public uniswapFactory;
    INonfungiblePositionManager public uniswapPositionManager;
    IWETH9 public weth;
    ISplitFactoryV2 public splitFactory;

    constructor(
        address initialOwner,
        address _uniswapFactory,
        address _uniswapPositionManager,
        address _weth,
        address _splitFactory
    ) Ownable(initialOwner) {
        buyFeePercent = 5;
        graduationFeePercent = 5;
        protocolFeePercent = 30;
        creatorFeePercent = 70;
        marketStatsPrice = 40000;
        poolFeePercent = 10000; // 1% as per the original contract
        liquidityPoolVolumeThreshold = 0.5 ether; // As per the original contract

        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
        uniswapPositionManager = INonfungiblePositionManager(
            _uniswapPositionManager
        );
        weth = IWETH9(_weth);
        splitFactory = ISplitFactoryV2(_splitFactory);
    }

    function setBuyFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10, "Fee percent cannot exceed 10%");
        buyFeePercent = _feePercent;
    }

    function setGraduationFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10, "Fee percent cannot exceed 10%");
        graduationFeePercent = _feePercent;
    }

    function setCreatorFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 100, "Fee percent cannot exceed 100%");
        creatorFeePercent = _feePercent;
        protocolFeePercent = 100 - _feePercent;
    }

    function setMarketStatsPrice(uint256 _price) external onlyOwner {
        marketStatsPrice = _price;
    }

    function setPoolFeePercent(uint24 _poolFeePercent) external onlyOwner {
        poolFeePercent = _poolFeePercent;
    }

    function setLiquidityPoolVolumeThreshold(
        uint256 _threshold
    ) external onlyOwner {
        liquidityPoolVolumeThreshold = _threshold;
    }

    function setUniswapFactory(address _uniswapFactory) external onlyOwner {
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
    }

    function setUniswapPositionManager(
        address _uniswapPositionManager
    ) external onlyOwner {
        uniswapPositionManager = INonfungiblePositionManager(
            _uniswapPositionManager
        );
    }

    function setWETH(address _weth) external onlyOwner {
        weth = IWETH9(_weth);
    }

    function setSplitFactory(address _splitFactory) external onlyOwner {
        splitFactory = ISplitFactoryV2(_splitFactory);
    }
}
