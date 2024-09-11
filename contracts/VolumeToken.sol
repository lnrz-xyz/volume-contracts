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
    IERC20 private constant STREAMZ =
        IERC20(0x499A12387357e3eC8FAcc011A2AB662e8aBdBd8f);

    // Constants
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    UD60x18 private immutable K;
    uint256 private immutable CREATOR_MAX_BUY;
    uint256 private immutable MINIMUM_WETH;

    uint256 public immutable liquidityPoolVolumeThreshold;

    // Storage variables

    uint256 public uniswapLiquidityPositionTokenID;
    ISplitWalletV2 public split;
    SplitV2Lib.Split public splitData;

    string private _uri;

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

    event FeesClaimed(uint256 baseFees, uint256 marketStatsFees);

    event LPDistributed(uint256 amount0, uint256 amount1);

    // constructor --------------------------------------

    constructor(
        address _config,
        string memory name,
        string memory symbol,
        string memory uri_
    ) payable Ownable(msg.sender) ERC20(name, symbol) {
        config = VolumeConfiguration(_config);
        liquidityPoolVolumeThreshold = config.liquidityPoolVolumeThreshold();

        K = ud(liquidityPoolVolumeThreshold).div(ud(400_000_000 * 1e18));
        // creator max buy is 10% of the supply
        CREATOR_MAX_BUY = TOTAL_SUPPLY / 10;
        _uri = uri_;
        MINIMUM_WETH = config.minimumWETH();

        _mint(address(this), TOTAL_SUPPLY);
    }

    // modifiers ----------------------------------------
    modifier onlyProtocol() {
        require(msg.sender == config.owner(), "Not the protocol");
        _;
    }

    // admin --------------------------------------------

    function setURI(string memory uri_) external onlyOwner {
        _uri = uri_;
    }

    // read functions -----------------------------------

    function uri() public view returns (string memory) {
        return _uri;
    }

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

    // Combined binary search function for buy and sell operations
    function findTokenBuyAmount(
        uint256 etherAmount,
        uint256 maxSlippage,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view returns (uint256) {
        uint256 lower = lowerBound;
        uint256 upper = upperBound;
        while (lower < upper) {
            uint256 mid = lower + (upper - lower) / 2;
            uint256 price = getBuyPrice(mid);
            if (price < etherAmount) {
                lower = mid + 1;
            } else if (price > etherAmount) {
                upper = mid;
            } else {
                break;
            }
        }
        uint256 finalPrice = getBuyPrice(lower - 1);

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

        return findTokenBuyAmount(eth, maxSlippage, lower, upper);
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
            actualAmount = findTokenBuyAmount(
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
            if (address(this).balance - feesEarned > MINIMUM_WETH) {
                (
                    address pool,
                    uint128 liquidityAdded,
                    uint256 tokenID
                ) = graduateToken();
                emit CurveEnded(pool, liquidityAdded, tokenID);
            } else {
                _burn(address(this), balanceOf(address(this)));
                emit CurveEnded(address(0), 0, 0);
            }
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
        volume += price;
        bool willGraduate = volume >= liquidityPoolVolumeThreshold;
        if (willGraduate) {
            // if the price makes the total liquidity drop below the minimum weth, we will set willGraduate to false
            // we will then change the amount sold to only the amount bringing the liquidity - price to minimum weth
            if (address(this).balance - feesEarned - price < MINIMUM_WETH) {
                willGraduate = false;
                // the difference between the current balance and the minimum weth
                price =
                    MINIMUM_WETH -
                    (address(this).balance - feesEarned - price);
                sellAmount = balanceOf(msg.sender);
                feesEarned += MINIMUM_WETH;
            }
        }

        require(price >= minAmountOut, "Slippage tolerance exceeded");

        _transfer(msg.sender, address(this), sellAmount);
        payable(msg.sender).sendValue(price);

        if (volume >= liquidityPoolVolumeThreshold) {
            _pause();
            if (willGraduate) {
                (
                    address pool,
                    uint128 liquidityAdded,
                    uint256 tokenID
                ) = graduateToken();
                emit CurveEnded(pool, liquidityAdded, tokenID);
            } else {
                _burn(address(this), balanceOf(address(this)));
                emit CurveEnded(address(0), 0, 0);
            }
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

    function graduateToken() private returns (address, uint128, uint256) {
        address pool = _createOrGetPool();
        uint256 liquidity = _prepareGraduationLiquidity();
        uint256 activeSupply = getTokensHeldInCurve();
        if (activeSupply > balanceOf(address(this))) {
            activeSupply = balanceOf(address(this));
        }

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

    function purchaseMarketStats() external {
        require(!boughtMarketStats[msg.sender], "Already purchased");
        boughtMarketStats[msg.sender] = true;

        STREAMZ.transferFrom(
            msg.sender,
            address(this),
            config.marketStatsPrice()
        );
    }

    function purchasedMarketStats(address holder) public view returns (bool) {
        return boughtMarketStats[holder];
    }

    // fees and splits ----------------------------------

    function claimFees() public nonReentrant {
        if (feesEarned > address(this).balance) {
            feesEarned = address(this).balance;
        }
        // protocol fee percent
        uint256 protocolFee = (feesEarned * config.protocolFeePercent()) / 100;
        // creator fee percent
        uint256 creatorFee = (feesEarned * config.creatorFeePercent()) / 100;

        feesEarned -= creatorFee + protocolFee;

        payable(owner()).sendValue(creatorFee);
        payable(config.owner()).sendValue(protocolFee);

        uint256 claimedMarketPurchaseValue = marketPurchaseValue;
        if (claimedMarketPurchaseValue > 0) {
            marketPurchaseValue = 0;

            STREAMZ.transfer(
                owner(),
                (marketPurchaseValue * config.creatorFeePercent()) / 100
            );
            STREAMZ.transfer(config.owner(), STREAMZ.balanceOf(address(this)));
        }

        emit FeesClaimed(creatorFee + protocolFee, claimedMarketPurchaseValue);
    }

    function distributeLP() public nonReentrant returns (uint256, uint256) {
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

        // Ensure correct token order
        (amount0, amount1) = address(this) < address(config.weth())
            ? (amount0, amount1)
            : (amount1, amount0);

        // Transfer to split contract
        require(
            IERC20(address(this)).transfer(address(split), amount0),
            "Transfer of token0 failed"
        );
        require(
            IERC20(address(config.weth())).transfer(address(split), amount1),
            "Transfer of token1 failed"
        );

        // Distribute
        split.distribute(splitData, address(this), msg.sender);
        split.distribute(splitData, address(config.weth()), msg.sender);

        emit LPDistributed(amount0, amount1);

        return (amount0, amount1);
    }

    function createSplitData() public view returns (SplitV2Lib.Split memory) {
        // Maximum number of recipients (protocol, owner, and up to 10 top holders)
        uint8 maxRecipients = 12;
        address[] memory recipients = new address[](maxRecipients);
        uint256[] memory allocations = new uint256[](maxRecipients);
        uint256 totalAllocation = 0;
        uint8 recipientCount = 0;
        uint16 distributionIncentive = 0;

        // Protocol
        recipients[recipientCount] = config.owner();
        allocations[recipientCount] = 20;
        totalAllocation += 20;
        recipientCount++;

        // Owner
        recipients[recipientCount] = owner();
        allocations[recipientCount] = 30;
        totalAllocation += 30;
        recipientCount++;

        // Top holders
        uint256 remainingAllocation = 50; // 100 - 20 - 30
        uint256 allocationPerHolder = 5;
        for (uint8 i = 0; i < 10 && recipientCount < maxRecipients; i++) {
            address holder = topHolders[i];
            if (holder != address(0)) {
                recipients[recipientCount] = holder;
                allocations[recipientCount] = allocationPerHolder;
                totalAllocation += allocationPerHolder;
                remainingAllocation -= allocationPerHolder;
                recipientCount++;
            }
        }

        // If there are fewer than 10 top holders, distribute remaining allocation
        if (remainingAllocation > 0 && recipientCount > 2) {
            uint256 extraAllocation = remainingAllocation /
                (recipientCount - 2);
            for (uint8 i = 2; i < recipientCount; i++) {
                allocations[i] += extraAllocation;
                totalAllocation += extraAllocation;
            }
        }

        // Create final arrays with exact size
        address[] memory finalRecipients = new address[](recipientCount);
        uint256[] memory finalAllocations = new uint256[](recipientCount);
        for (uint8 i = 0; i < recipientCount; i++) {
            finalRecipients[i] = recipients[i];
            finalAllocations[i] = allocations[i];
        }

        return
            SplitV2Lib.Split({
                recipients: finalRecipients,
                allocations: finalAllocations,
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
        if (account == address(0) || account == address(this)) {
            return;
        }

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
    ) external {}

    // emergency -----------------------------------------
    function pause() external onlyProtocol {
        _pause();
    }

    function ejectLP() public onlyProtocol {
        config.uniswapPositionManager().safeTransferFrom(
            address(this),
            config.owner(),
            uniswapLiquidityPositionTokenID
        );
    }
}
