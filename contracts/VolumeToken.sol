// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./FullMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./IWETH9.sol";
import "./INonfungiblePositionManager.sol";
import "hardhat/console.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import "splits-v2/splitters/SplitFactoryV2.sol";
import {SplitV2Lib} from "splits-v2/libraries/SplitV2.sol";

contract VolumeToken is ERC20, ERC20Permit, Ownable, Pausable {
    using Address for address payable;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    address payable private protocol =
        payable(0x49D4de8Fc7fD8FceEf03AA5b7b191189bFbB637b);
    IERC20 private constant STREAMZ =
        IERC20(0x499A12387357e3eC8FAcc011A2AB662e8aBdBd8f);

    // total erc20 supply
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;

    // constant K for bonding curve calculation
    uint256 public constant K = (4 * 1e18) / (200_000_000 ** 2);

    // the amount we match for liquidity when creating the pool
    uint256 public constant LIQUIDITY_POOL_AMOUNT = 200_000_000 * 1e18;

    // max creator amount
    uint256 public constant CREATOR_MAX_BUY = 10000_000_000 * 1e18;
    // amount to burn after pool creation
    uint256 public constant BURN_AMOUNT = 200_000_000 * 1e18;

    uint256 public constant LIQUIDITY_POOL_VOLUME_THRESHOLD = 1 ether;

    uint256 public marketStatsPrice = 40000;

    // pool fee tier (1%)
    uint24 public constant POOL_FEE = 10000;
    // the fee percent for buying tokens
    uint256 public buyFeePercent = 10;

    // how much of the fees go to the protocol vs the creator
    uint256 public protocolFeePercent = 30;
    uint256 public creatorFeePercent = 70;

    IUniswapV3Factory private immutable uniswapFactory;
    INonfungiblePositionManager private immutable uniswapPositionManager;
    IWETH9 private immutable WETH;
    SplitFactoryV2 private immutable splitFactory;

    event Buy(
        address indexed trader,
        uint256 newSupply,
        uint256 newBuyPrice,
        uint256 amount,
        uint256 ethAmount
    );

    event Sell(
        address indexed trader,
        uint256 newSupply,
        uint256 newBuyPrice,
        uint256 amount,
        uint256 ethAmount
    );

    event CurveEnded(address indexed pool, uint128 liquidity, uint256 tokenId);

    event RewardsClaimed(
        address indexed holder,
        address indexed token,
        uint256 amount,
        uint32 destination
    );

    // holder -> amount
    // we use this instead of IERC20.balanceOf to ensure at the end of the curve we have a snapshot state of all holders
    // we also can use the enumerability to count holders easily off-chain
    EnumerableMap.AddressToUintMap private curveHoldings;

    // token address -> amount
    EnumerableMap.AddressToUintMap private rewards;
    // token address -> LayerZero endpoint id
    mapping(address => uint32) private rewardDestinations;
    // holder -> token address -> claimed
    mapping(address => mapping(address => bool)) private rewardClaims;
    // sponsor -> token address -> amount
    mapping(address => mapping(address => uint256)) private sponsors;

    mapping(address => bool) private boughtMarketStats;

    address[10] private topHolders;
    mapping(address => bool) private isTopHolder;

    uint256 private volume;

    uint256 private feesEarned;
    uint256 marketPurchaseValue;

    constructor(
        address _factory,
        address _positions,
        address _weth,
        address _splitFactory,
        string memory name,
        string memory symbol
    ) payable Ownable(msg.sender) ERC20(name, symbol) ERC20Permit(name) {
        require(msg.value == 0.0004 ether, "Incorrect deployment fee");
        uniswapFactory = IUniswapV3Factory(_factory);
        uniswapPositionManager = INonfungiblePositionManager(_positions);
        WETH = IWETH9(_weth);
        splitFactory = SplitFactoryV2(_splitFactory);
        IERC20(address(WETH)).approve(address(_factory), type(uint256).max);

        _mint(address(this), TOTAL_SUPPLY);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory
    ) external {
        // TODO test with this uncommented
        // IERC20(WETH).transfer(msg.sender, amount0Delta > amount1Delta ? uint256(amount0Delta) : uint256(amount1Delta));
    }

    modifier onlyProtocol() {
        require(msg.sender == protocol, "Not the protocol");
        _;
    }

    function setProtocol(address payable protocol_) public onlyProtocol {
        protocol = protocol_;
    }

    function setBuyFeePercent(uint256 _feePercent) public onlyProtocol {
        require(_feePercent <= 10, "Fee percent cannot exceed 10%");
        buyFeePercent = _feePercent;
    }

    function setCreatorFeePercent(uint256 _feePercent) public onlyProtocol {
        require(_feePercent <= 100, "Fee percent cannot exceed 100%");
        creatorFeePercent = _feePercent;
        protocolFeePercent = 100 - _feePercent;
    }

    function getCurveBalance(address holder) public view returns (uint256) {
        return curveHoldings.get(holder);
    }

    function getCurveHolders() public view returns (address[] memory) {
        return curveHoldings.keys();
    }

    function getTokensHeldInCurve() public view returns (uint256) {
        return TOTAL_SUPPLY - balanceOf(address(this));
    }

    function getCurveHoldersLength() public view returns (uint256) {
        return curveHoldings.length();
    }

    function getThreshold() public pure returns (uint256) {
        return LIQUIDITY_POOL_VOLUME_THRESHOLD;
    }

    function getVolume() public view returns (uint256) {
        return volume;
    }

    function pause() external onlyProtocol {
        _pause();
    }

    function getRewardDestination(address token) public view returns (uint32) {
        return rewardDestinations[token];
    }

    function getRewards() public view returns (address[] memory) {
        return rewards.keys();
    }

    function getReward(address token) public view returns (uint256) {
        return rewards.get(token);
    }

    function getRewardIsClaimed(
        address holder,
        address token
    ) public view returns (bool) {
        return rewardClaims[holder][token];
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        UD60x18 currentSupply = ud(getTokensHeldInCurve());
        UD60x18 newSupply = ud(getTokensHeldInCurve()).add(ud(amount));

        return
            ud(K)
                .mul(newSupply.powu(2).sub(currentSupply.powu(2)))
                .div(ud(2e18))
                .unwrap();
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        UD60x18 currentSupply = ud(getTokensHeldInCurve());
        UD60x18 newSupply = ud(getTokensHeldInCurve()).sub(ud(amount));

        return
            ud(K)
                .mul(currentSupply.powu(2).sub(newSupply.powu(2)))
                .div(ud(2e18))
                .unwrap();
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

        return findTokenAmountForSell(eth, maxSlippage, lower, upper);
    }

    // binary search to find the amount of tokens to sell for a given amount of eth
    function findTokenAmountForSell(
        uint256 receivedEther,
        uint256 maxSlippage,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view returns (uint256) {
        uint256 lower = lowerBound;
        uint256 upper = upperBound;
        while (lower < upper) {
            uint256 mid = lower + (upper - lower) / 2;
            uint256 price = getSellPrice(mid);
            if (price < receivedEther) {
                lower = mid + 1;
            } else if (price > receivedEther) {
                upper = mid;
            } else {
                break;
            }
        }
        uint256 finalPrice = getSellPrice(lower - 1);
        require(
            finalPrice <= receivedEther &&
                (receivedEther - finalPrice) * 100 <= maxSlippage * finalPrice,
            "Slippage too high"
        );
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

        return findTokenAmountForBuy(eth, maxSlippage, lower, upper);
    }

    // binary search to find the amount of tokens to buy for a given amount of eth
    function findTokenAmountForBuy(
        uint256 paidEther,
        uint256 maxSlippage,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view returns (uint256) {
        uint256 lower = lowerBound;
        uint256 upper = upperBound;
        while (lower < upper) {
            uint256 mid = lower + (upper - lower) / 2;
            uint256 price = getBuyPrice(mid);
            if (price < paidEther) {
                lower = mid + 1;
            } else if (price > paidEther) {
                upper = mid;
            } else {
                break;
            }
        }
        uint256 finalPrice = getBuyPrice(lower - 1);
        console.log("Final Price: %d (%d)", finalPrice, paidEther);
        require(
            finalPrice <= paidEther &&
                (paidEther - finalPrice) * 100 <= maxSlippage * finalPrice,
            "Slippage too high"
        );
        return lower;
    }

    function buy(
        uint256 amount,
        uint256 maxSlippage
    ) external payable whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        if (_msgSender() == owner()) {
            require(
                balanceOf(_msgSender()) + amount <= CREATOR_MAX_BUY,
                "Amount exceeds max buy for creator"
            );
        }

        uint256 price = getBuyPrice(amount);
        uint256 fee = (price * buyFeePercent) / 100;

        if (msg.value >= price + fee) {
            // refund the difference if they oversend
            uint256 refund = msg.value - price - fee;
            if (refund > 0) {
                payable(_msgSender()).sendValue(refund);
            }

            _buy(amount, price, fee);
        } else {
            // try to complete transaction anyway if they undersend, use slippage
            uint256 actualAmount = findTokenAmountForBuy(
                msg.value - (msg.value * buyFeePercent) / 100,
                maxSlippage,
                amount < 10 ? 0 : amount / 10,
                amount * 4
            );
            require(
                actualAmount > 0,
                "Not enough input to buy the minimum amount of tokens"
            );
            price = getBuyPrice(actualAmount);
            fee = (price * buyFeePercent) / 100;
            uint256 refund = msg.value - price - fee;
            if (refund > 0) {
                payable(_msgSender()).sendValue(refund);
            }

            _buy(actualAmount, price, fee);
        }

        // if (amount + getTokensHeldInCurve() >= TRADEABLE_SUPPLY) {
        if (volume >= LIQUIDITY_POOL_VOLUME_THRESHOLD) {
            // curve ends here
            _pause();

            address pool = IUniswapV3Factory(uniswapFactory).getPool(
                address(this),
                address(WETH),
                POOL_FEE
            );
            if (pool == address(0)) {
                pool = IUniswapV3Factory(uniswapFactory).createPool(
                    address(this),
                    address(WETH),
                    POOL_FEE
                );
            }
            require(pool != address(0), "Pool does not exist");

            uint160 sqrtPriceX96 = uint160((sqrt(1) * 2) ** 96);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);

            uint256 liquidity = address(this).balance - feesEarned;

            IWETH9(WETH).deposit{value: liquidity}();

            uint256 activeSupply = TOTAL_SUPPLY - balanceOf(address(this));

            // Approve the Nonfungible Position Manager to spend tokens
            IERC20(address(this)).approve(
                address(uniswapPositionManager),
                activeSupply
            );
            IERC20(address(WETH)).approve(
                address(uniswapPositionManager),
                liquidity
            );

            (address token0, address token1) = address(this) < address(WETH)
                ? (address(this), address(WETH))
                : (address(WETH), address(this));
            (uint256 tk0AmountToMint, uint256 tk1AmountToMint) = (address(
                this
            ) == token0)
                ? (activeSupply, liquidity)
                : (liquidity, activeSupply);

            (uint256 amount0min, uint256 amount1min) = (address(this) == token0)
                ? (uint256(0), liquidity)
                : (liquidity, uint256(0));

            (
                uint256 tokenId,
                uint128 liquidityAdded,
                ,

            ) = uniswapPositionManager.mint(
                    INonfungiblePositionManager.MintParams({
                        token0: token0,
                        token1: token1,
                        fee: POOL_FEE,
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

            _burn(address(this), BURN_AMOUNT);
            _transfer(address(this), pool, balanceOf(address(this))); // ????

            splitFactory.createSplit(createSplitData(), protocol, owner());

            emit CurveEnded(pool, liquidityAdded, tokenId);
        }
    }

    function createSplitData() public pure returns (SplitV2Lib.Split memory) {
        // the protocol and owner get 20 percent
        // the top 10 holders split the other 80 percent
        address[] memory recipients = new address[](12);
        uint256[] memory allocations = new uint256[](12);
        uint256 totalAllocation = 0;
        uint256 distributionIncentive = 0;

        // protocol
        recipients[0] = protocol;
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

    function calculateSqrtPriceX96(
        uint256 priceToken1InToken0
    ) public pure returns (uint160) {
        // priceToken1InToken0 is the price of token1 in terms of token0, scaled up by 1e18
        uint256 sqrtPriceX96 = sqrt(priceToken1InToken0) * 2 ** 96;
        return uint160(sqrtPriceX96);
    }

    function _buy(uint256 amount, uint256 price, uint256 fee) internal {
        // TODO do fees earned or just transfer to protocol and creator?
        feesEarned += fee;
        volume += msg.value;

        _transfer(address(this), _msgSender(), amount);
        emit Buy(
            _msgSender(),
            getTokensHeldInCurve(),
            getBuyPrice(1e18),
            amount,
            price
        );
    }

    // maybe add slippage and desired sale price to sell, or a separate function for this
    function sell(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        uint256 price = getSellPrice(amount);

        payable(_msgSender()).sendValue(price);

        volume += price;

        _transfer(_msgSender(), address(this), amount);

        emit Sell(
            _msgSender(),
            getTokensHeldInCurve(),
            getBuyPrice(1e18),
            amount,
            price
        );
    }

    // TODO make it take streamz
    function purchaseMarketStats() external payable {
        require(!boughtMarketStats[_msgSender()], "Already purchased");
        boughtMarketStats[_msgSender()] = true;

        require(msg.value == marketStatsPrice, "Insufficient payment");
        marketPurchaseValue += msg.value;

        // STREAMZ.transferFrom(_msgSender(), address(this), marketStatsPrice);
    }

    function purchasedMarketStats(address holder) public view returns (bool) {
        return boughtMarketStats[holder];
    }

    // TODO remove
    function testWithdrawRemoveBeforeProd() public onlyOwner {
        payable(_msgSender()).sendValue(address(this).balance);
    }

    function claimFees() public onlyOwner {
        // protocol fee percent
        uint256 protocolFee = (feesEarned * protocolFeePercent) / 100;
        // creator fee percent
        uint256 creatorFee = (feesEarned * creatorFeePercent) / 100;

        feesEarned -= creatorFee + protocolFee;

        payable(owner()).sendValue(creatorFee);
        protocol.sendValue(protocolFee);

        // TODO uncomment before prod
        marketPurchaseValue = 0;
        payable(protocol).sendValue(marketPurchaseValue); // TODO remove!!
        // STREAMZ.transfer(owner(), (marketPurchaseValue * creatorFeePercent) / 100);
        // STREAMZ.transfer(protocol, STREAMZ.balanceOf(address(this)));
    }

    // override transfer and transferFrom to modify curveHoldings
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._transfer(from, to, amount);
        if (!paused()) {
            uint256 balance = curveHoldings.get(_msgSender());
            require(balance >= amount, "Insufficient balance");
            if (balance - amount == 0) {
                curveHoldings.remove(_msgSender());
            } else {
                curveHoldings.set(_msgSender(), balance - amount);
            }
            // update recipient balance
            (, uint256 recBalance) = curveHoldings.tryGet(to);
            curveHoldings.set(to, recBalance + amount);

            updateTopHolders(to);
            updateTopHolders(from);
        }
        return success;
    }

    function updateTopHolders(address account) internal {
        uint256 balance = balanceOf(account);

        if (isTopHolder[account]) {
            sortTopHolders();
        } else {
            for (uint8 i = 0; i < topHolders.length; i++) {
                if (balance > balanceOf(topHolders[i])) {
                    insertTopHolder(account, i);
                    break;
                }
            }
        }
    }

    function insertTopHolder(address account, uint8 index) internal {
        for (uint8 i = topHolders.length - 1; i > index; i--) {
            topHolders[i] = topHolders[i - 1];
        }
        topHolders[index] = account;
        isTopHolder[account] = true;
    }

    function sortTopHolders() internal {
        for (uint8 i = 0; i < topHolders.length; i++) {
            for (uint8 j = i + 1; j < topHolders.length; j++) {
                if (balanceOf(topHolders[j]) > balanceOf(topHolders[i])) {
                    address temp = topHolders[i];
                    topHolders[i] = topHolders[j];
                    topHolders[j] = temp;
                }
            }
        }
    }

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
}
