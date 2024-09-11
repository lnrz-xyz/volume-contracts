// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "./VolumeConfiguration.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VolumeToken is
    ERC20,
    Ownable,
    Pausable,
    IERC721Receiver,
    ReentrancyGuard
{
    using Address for address payable;

    VolumeConfiguration private immutable config;

    // Constants
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    UD60x18 private immutable K;
    uint256 private immutable CREATOR_MAX_BUY;

    uint256 public immutable liquidityPoolVolumeThreshold;

    // Storage variables

    uint256 public uniswapLiquidityPositionTokenID;
    ISplitWalletV2 public split;
    SplitV2Lib.Split public splitData;

    mapping(address => mapping(address => uint256)) private sponsors;
    mapping(address => bool) private boughtMarketStats;
    address[10] public topHolders;
    mapping(address => uint256) public topHolderHoldings;
    mapping(address => bool) private isTopHolder;

    uint256 public volume;
    uint256 public feesEarned;
    uint256 public marketPurchaseValue;

    // Events
    event Trade(
        address indexed trader,
        uint256 newSupply,
        uint256 newBuyPrice,
        uint256 amount,
        uint256 ethAmount,
        bool isBuy
    );

    event CurveEnded(address indexed pool, uint128 liquidity, uint256 tokenID);

    event FeesClaimed(
        uint256 baseFees,
        uint256 marketStatsFees,
        uint256 lpAmount0,
        uint256 lpAmount1
    );

    // constructor --------------------------------------

    constructor(
        address _config,
        string memory name,
        string memory symbol
    ) payable Ownable(msg.sender) ERC20(name, symbol) {
        config = VolumeConfiguration(_config);
        liquidityPoolVolumeThreshold = config.liquidityPoolVolumeThreshold();

        K = ud(liquidityPoolVolumeThreshold).div(ud(800_000_000 * 1e18));
        // creator max buy is 10% of the supply
        CREATOR_MAX_BUY = TOTAL_SUPPLY / 10;

        _mint(address(this), TOTAL_SUPPLY);
    }

    // modifiers ----------------------------------------
    modifier onlyProtocol() {
        require(msg.sender == config.owner(), "Not the protocol");
        _;
    }

    // read functions -----------------------------------

    function getTokensHeldInCurve() public view returns (uint256) {
        return TOTAL_SUPPLY - balanceOf(address(this));
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        UD60x18 currentSupply = ud(getTokensHeldInCurve());
        UD60x18 newSupply = currentSupply.add(ud(amount));

        return K.mul(newSupply.sub(currentSupply)).unwrap();
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            return getSellPrice(balanceOf(msg.sender));
        }

        UD60x18 currentSupply = ud(getTokensHeldInCurve());
        UD60x18 newSupply = currentSupply.sub(ud(amount));

        return K.mul(currentSupply.sub(newSupply)).unwrap();
    }

    function getAmountByETHSell(
        uint256 eth,
        uint256 maxSlippage
    ) external view returns (uint256) {
        uint256 lower = 0;
        uint256 upper = getTokensHeldInCurve();
        // initial range estimation
        while (getSellPrice(upper) < eth) {
            lower = upper - (upper / 10);
            upper *= 2;
        }

        return findTokenAmount(false, eth, maxSlippage, lower, upper);
    }

    // Combined binary search function for buy and sell operations
    function findTokenAmount(
        bool isBuy,
        uint256 etherAmount,
        uint256 maxSlippage,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view returns (uint256) {
        uint256 lower = lowerBound;
        uint256 upper = upperBound;
        while (lower < upper) {
            uint256 mid = lower + (upper - lower) / 2;
            uint256 price = isBuy ? getBuyPrice(mid) : getSellPrice(mid);
            if (price < etherAmount) {
                lower = mid + 1;
            } else if (price > etherAmount) {
                upper = mid;
            } else {
                break;
            }
        }
        uint256 finalPrice = isBuy
            ? getBuyPrice(lower - 1)
            : getSellPrice(lower - 1);

        if (maxSlippage > 0) {
            require(
                finalPrice <= etherAmount &&
                    (etherAmount - finalPrice) * 100 <=
                    maxSlippage * finalPrice,
                "Slippage too high"
            );
        }
        return lower;
    }

    function getAmountByETHBuy(
        uint256 eth,
        uint256 maxSlippage
    ) external view returns (uint256) {
        uint256 lower = 0;
        uint256 upper = 1;
        while (getBuyPrice(upper) < eth) {
            lower = upper - (upper / 10);
            upper *= 2;
        }

        return findTokenAmount(true, eth, maxSlippage, lower, upper);
    }

    // trading ------------------------------------------

    function buy(
        uint256 amount,
        uint256 maxSlippage
    ) public payable whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        if (msg.sender == owner()) {
            require(
                balanceOf(msg.sender) + amount <= CREATOR_MAX_BUY,
                "Amount exceeds max buy for creator"
            );
        }

        uint256 price = getBuyPrice(amount);
        uint256 fee = (price * config.buyFeePercent()) / 100;
        uint256 totalCost = price + fee;

        uint256 actualAmount;
        uint256 refund;

        if (msg.value >= totalCost) {
            actualAmount = amount;
            refund = msg.value - totalCost;
        } else {
            actualAmount = findTokenAmount(
                true,
                msg.value - (msg.value * config.buyFeePercent()) / 100,
                maxSlippage,
                amount < 10 ? 0 : amount / 10,
                amount * 4
            );
            require(
                actualAmount > 0,
                "Not enough input to buy the minimum amount of tokens"
            );
            price = getBuyPrice(actualAmount);
            fee = (price * config.buyFeePercent()) / 100;
            refund = msg.value - price - fee;
        }

        if (refund > 0) {
            payable(msg.sender).sendValue(refund);
        }

        _buy(actualAmount, price, fee);

        if (volume >= liquidityPoolVolumeThreshold) {
            _pause();
            (
                address pool,
                uint128 liquidityAdded,
                uint256 tokenID
            ) = graduateToken();
            emit CurveEnded(pool, liquidityAdded, tokenID);
        }
    }

    function _buy(uint256 amount, uint256 price, uint256 fee) internal {
        feesEarned += fee;
        volume += price + fee;

        _transfer(address(this), msg.sender, amount);
        emit Trade(
            msg.sender,
            getTokensHeldInCurve(),
            getBuyPrice(1e18),
            amount,
            price,
            true
        );
    }
    function sell(
        uint256 amount,
        uint256 minAmountOut
    ) external whenNotPaused nonReentrant {
        uint256 sellAmount = amount == 0 ? balanceOf(msg.sender) : amount;
        uint256 price = getSellPrice(sellAmount);

        // Check if this sale would cross the threshold
        if (volume + price >= liquidityPoolVolumeThreshold) {
            // Calculate the maximum amount that can be sold without crossing the threshold
            uint256 maxSellAmount = findMaxSellAmount(sellAmount);
            require(
                maxSellAmount > 0,
                "Cannot sell any tokens without crossing threshold"
            );

            sellAmount = balanceOf(msg.sender) > maxSellAmount + 1
                ? maxSellAmount + 1
                : balanceOf(msg.sender);
            price = getSellPrice(sellAmount);
        }

        require(price >= minAmountOut, "Slippage tolerance exceeded");

        _transfer(msg.sender, address(this), sellAmount);
        payable(msg.sender).sendValue(price);

        volume += price;

        if (volume >= liquidityPoolVolumeThreshold) {
            _pause();
            (
                address pool,
                uint128 liquidityAdded,
                uint256 tokenID
            ) = graduateToken();
            emit CurveEnded(pool, liquidityAdded, tokenID);
        }

        emit Trade(
            msg.sender,
            getTokensHeldInCurve(),
            getBuyPrice(1e18),
            sellAmount,
            price,
            false
        );
    }

    function findMaxSellAmount(
        uint256 initialAmount
    ) internal view returns (uint256) {
        uint256 lower = 0;
        uint256 upper = initialAmount;
        uint256 target = liquidityPoolVolumeThreshold - volume;

        while (lower < upper) {
            uint256 mid = (lower + upper + 1) / 2;
            uint256 price = getSellPrice(mid);

            if (price <= target) {
                lower = mid;
            } else {
                upper = mid - 1;
            }
        }

        return lower;
    }

    function graduateToken() private returns (address, uint128, uint256) {
        address pool = _createOrGetPool();
        uint256 liquidity = _prepareGraduationLiquidity();
        uint256 activeSupply = TOTAL_SUPPLY - balanceOf(address(this));

        _approveTokensForUniswap(activeSupply, liquidity);

        (uint256 tokenID, uint128 liquidityAdded) = _addLiquidityToUniswap(
            activeSupply,
            liquidity
        );

        uniswapLiquidityPositionTokenID = tokenID;

        _finalizeGraduation();

        return (pool, liquidityAdded, tokenID);
    }

    function _createOrGetPool() private returns (address) {
        address pool = config.uniswapFactory().getPool(
            address(this),
            address(config.weth()),
            config.poolFeePercent()
        );
        if (pool == address(0)) {
            pool = config.uniswapFactory().createPool(
                address(this),
                address(config.weth()),
                config.poolFeePercent()
            );
            uint160 sqrtPriceX96 = uint160((sqrt(1) * 2) ** 96);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        }
        require(pool != address(0), "Pool does not exist");
        return pool;
    }

    function _prepareGraduationLiquidity() private returns (uint256) {
        uint256 liquidity = address(this).balance - feesEarned;
        uint256 graduationFee = (liquidity * config.graduationFeePercent()) /
            100;
        payable(config.owner()).sendValue(graduationFee);
        liquidity -= graduationFee;
        IWETH9(config.weth()).deposit{value: liquidity}();
        return liquidity;
    }

    function _approveTokensForUniswap(
        uint256 activeSupply,
        uint256 liquidity
    ) private {
        IERC20(address(this)).approve(
            address(config.uniswapPositionManager()),
            activeSupply
        );
        IERC20(address(config.weth())).approve(
            address(config.uniswapPositionManager()),
            liquidity
        );
    }

    function _addLiquidityToUniswap(
        uint256 activeSupply,
        uint256 liquidity
    ) private returns (uint256, uint128) {
        (address token0, address token1) = address(this) <
            address(config.weth())
            ? (address(this), address(config.weth()))
            : (address(config.weth()), address(this));
        (uint256 tk0AmountToMint, uint256 tk1AmountToMint) = address(this) ==
            token0
            ? (activeSupply, liquidity)
            : (liquidity, activeSupply);
        (uint256 amount0min, uint256 amount1min) = address(this) == token0
            ? (uint256(0), liquidity)
            : (liquidity, uint256(0));

        (
            uint256 tokenID,
            uint128 liquidityAdded,
            ,

        ) = INonfungiblePositionManager(config.uniswapPositionManager()).mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: config.poolFeePercent(),
                    tickLower: -887200,
                    tickUpper: 887200,
                    amount0Desired: tk0AmountToMint,
                    amount1Desired: tk1AmountToMint,
                    amount0Min: amount0min,
                    amount1Min: amount1min,
                    recipient: address(this),
                    deadline: block.timestamp + 1000
                })
            );

        return (tokenID, liquidityAdded);
    }

    function _finalizeGraduation() private {
        _burn(address(this), balanceOf(address(this)));

        splitData = createSplitData();
        split = ISplitWalletV2(
            config.splitFactory().createSplit(
                splitData,
                config.owner(),
                owner()
            )
        );
    }

    // market stats -------------------------------------

    function purchaseMarketStats() external payable {
        require(!boughtMarketStats[msg.sender], "Already purchased");
        boughtMarketStats[msg.sender] = true;

        // TODO remove before prod (take eth in the mean time)
        require(msg.value == config.marketStatsPrice(), "Insufficient payment");
        marketPurchaseValue += msg.value;

        // TODO uncomment before prod
        // STREAMZ.transferFrom(msg.sender, address(this), marketStatsPrice);
    }

    function purchasedMarketStats(address holder) public view returns (bool) {
        return boughtMarketStats[holder];
    }

    // fees and splits ----------------------------------

    function claimFees() public nonReentrant {
        // protocol fee percent
        uint256 protocolFee = (feesEarned * config.protocolFeePercent()) / 100;
        // creator fee percent
        uint256 creatorFee = (feesEarned * config.creatorFeePercent()) / 100;

        feesEarned -= creatorFee + protocolFee;

        payable(owner()).sendValue(creatorFee);
        payable(config.owner()).sendValue(protocolFee);

        uint256 claimedMarketPurchaseValue = marketPurchaseValue;
        marketPurchaseValue = 0;
        payable(config.owner()).sendValue(marketPurchaseValue); // TODO remove before prod
        // TODO uncomment before prod
        // STREAMZ.transfer(owner(), (marketPurchaseValue * creatorFeePercent) / 100);
        // STREAMZ.transfer(protocol, STREAMZ.balanceOf(address(this)));

        if (paused()) {
            (uint256 amount0, uint256 amount1) = distributeLP();
            emit FeesClaimed(
                creatorFee + protocolFee,
                claimedMarketPurchaseValue,
                amount0,
                amount1
            );
        } else {
            emit FeesClaimed(
                creatorFee + protocolFee,
                claimedMarketPurchaseValue,
                0,
                0
            );
        }
    }

    function distributeLP() private returns (uint256, uint256) {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: uniswapLiquidityPositionTokenID,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (uint256 amount0, uint256 amount1) = config
            .uniswapPositionManager()
            .collect(params);

        // send it to the split
        (amount0, amount1) = address(this) < address(config.weth())
            ? (amount0, amount1)
            : (amount1, amount0);

        IERC20(address(this)).transfer(address(split), amount0);
        IERC20(address(config.weth())).transfer(address(split), amount1);

        split.distribute(splitData, address(this), msg.sender);
        split.distribute(splitData, address(config.weth()), msg.sender);

        return (amount0, amount1);
    }

    function createSplitData() public view returns (SplitV2Lib.Split memory) {
        // the protocol and owner get 20 percent
        // the top 10 holders split the other 80 percent
        address[] memory recipients = new address[](12);
        uint256[] memory allocations = new uint256[](12);
        uint256 totalAllocation = 0;
        uint16 distributionIncentive = 0;

        // protocol
        recipients[0] = config.owner();
        allocations[0] = 10;
        totalAllocation += 10;

        // owner
        recipients[1] = owner();
        allocations[1] = 10;
        totalAllocation += 10;

        // top holders

        for (uint8 i = 0; i < 10; i++) {
            recipients[i + 2] = address(0);
            allocations[i + 2] = 8;
            totalAllocation += 8;
        }

        return
            SplitV2Lib.Split({
                recipients: recipients,
                allocations: allocations,
                totalAllocation: totalAllocation,
                distributionIncentive: distributionIncentive
            });
    }

    // override transfer and transferFrom to modify curveHoldings
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);

        if (!paused()) {
            updateTopHolders(to);
            updateTopHolders(from);
        }
    }

    function updateTopHolders(address account) internal {
        uint256 balance = balanceOf(account);

        // Update or remove the account from topHolderHoldings
        if (balance > 0) {
            topHolderHoldings[account] = balance;
        } else {
            delete topHolderHoldings[account];
        }

        // Rebuild the top holders list
        address[10] memory newTopHolders;
        uint256[10] memory newTopHolderBalances;
        uint8 count = 0;

        // First, add the current account if it qualifies
        if (balance > 0) {
            newTopHolders[0] = account;
            newTopHolderBalances[0] = balance;
            count = 1;
        }

        // Then, go through existing top holders
        for (uint8 i = 0; i < 10 && count < 10; i++) {
            address holder = topHolders[i];
            if (holder != address(0) && holder != account) {
                uint256 holderBalance = balanceOf(holder);
                if (holderBalance > 0) {
                    // Insert the holder in the correct position
                    uint8 j = count;
                    while (
                        j > 0 && holderBalance > newTopHolderBalances[j - 1]
                    ) {
                        newTopHolders[j] = newTopHolders[j - 1];
                        newTopHolderBalances[j] = newTopHolderBalances[j - 1];
                        j--;
                    }
                    newTopHolders[j] = holder;
                    newTopHolderBalances[j] = holderBalance;
                    count++;
                }
            }
        }

        // Update the topHolders array and isTopHolder mapping
        for (uint8 i = 0; i < 10; i++) {
            address oldHolder = topHolders[i];
            address newHolder = newTopHolders[i];

            if (oldHolder != newHolder) {
                if (oldHolder != address(0)) {
                    isTopHolder[oldHolder] = false;
                }
                if (newHolder != address(0)) {
                    isTopHolder[newHolder] = true;
                }
                topHolders[i] = newHolder;
            }
        }
    }

    // utility -------------------------------------------

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // interface requirements ----------------------------

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory
    ) external {
        // TODO is this necessary?
    }

    // emergency -----------------------------------------
    function pause() external onlyProtocol {
        _pause();
    }

    // TODO remove before prod
    function testWithdrawRemoveBeforeProd() public onlyProtocol {
        payable(msg.sender).sendValue(address(this).balance);
    }

    function ejectLP() public onlyProtocol {
        config.uniswapPositionManager().safeTransferFrom(
            address(this),
            config.owner(),
            uniswapLiquidityPositionTokenID
        );
    }
}
