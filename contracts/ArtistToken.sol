// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./INonfungiblePositionManager.sol";
import "hardhat/console.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract ArtistToken is ERC20, ERC20Permit, Ownable, Pausable, OApp {
    using OptionsBuilder for bytes;
    using Address for address payable;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    IERC20 public constant streamz = IERC20(0x499A12387357e3eC8FAcc011A2AB662e8aBdBd8f);

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant TRADEABLE_SUPPLY = 200_000_000 * 1e18;
    uint256 public constant LIQUIDITY_VALUE = 4 ether;

    uint256 public constant K = (8 * 1e18) / (200000000 ** 2);

    uint256 public constant LIQUIDITY_POOL_AMOUNT = 200_000_000 * 1e18;

    uint256 public constant creatorAmount = 10_000_000 * 1e18;
    uint24 public constant poolFee = 10000;
    uint256 public buyFeePercent = 5;
    UD60x18 public maxSellFeePercent = ud(5);
    UD60x18 public noFeeProfitPercent = ud(5); // Profit at which no sell fee is charged
    UD60x18 public fullFeeProfitPercent = ud(20);
    uint256 public protocolFeePercent = 30;
    uint256 public creatorFeePercent = 70;

    address private uniswapRouter;
    address private uniswapFactory;
    address private uniswapPositionManager;
    address private WETH;

    event Buy(address indexed trader, uint256 newSupply, uint256 newBuyPrice, uint256 amount, uint256 ethAmount);

    event Sell(address indexed trader, uint256 newSupply, uint256 newBuyPrice, uint256 amount, uint256 ethAmount);

    EnumerableMap.AddressToUintMap private curveHoldings;

    EnumerableMap.AddressToUintMap private rewards;
    mapping(address => uint32) private rewardDestinations;
    mapping(address => mapping(address => bool)) private rewardClaims;
    mapping(address => mapping(address => uint256)) private sponsors;

    struct PurchaseData {
        UD60x18 totalInvested;
        UD60x18 totalTokensPurchased;
    }

    mapping(address => PurchaseData) public purchaseRecords;

    uint256 private volume;

    uint256 private feesEarned; // TODO make internal

    constructor(
        address _swapRouter,
        address _factory,
        address _positions,
        address _weth,
        string memory name,
        string memory symbol,
        address endpoint
    ) Ownable(msg.sender) ERC20(name, symbol) ERC20Permit(name) OApp(endpoint, msg.sender) {
        uniswapRouter = _swapRouter;
        uniswapFactory = _factory;
        uniswapPositionManager = _positions;
        WETH = _weth;
        _mint(address(this), TOTAL_SUPPLY);
    }

    modifier onlyProtocol() {
        require(msg.sender == protocol(), "Not the protocol");
        _;
    }

    function setBuyFeePercent(uint256 _feePercent) public onlyProtocol {
        require(_feePercent <= 10, "Fee percent cannot exceed 10%");
        buyFeePercent = _feePercent;
    }

    function setMaxSellFeePercent(uint256 _feePercent) public onlyProtocol {
        require(_feePercent <= 10, "Fee percent cannot exceed 10%");
        maxSellFeePercent = ud(_feePercent);
    }

    function setNoFeeProfitPercent(uint256 _profitPercent) public onlyProtocol {
        require(_profitPercent <= 100, "Profit percent cannot exceed 100%");
        noFeeProfitPercent = ud(_profitPercent);
    }

    function setFullFeeProfitPercent(uint256 _profitPercent) public onlyProtocol {
        require(_profitPercent <= 100, "Profit percent cannot exceed 100%");
        fullFeeProfitPercent = ud(_profitPercent);
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
        return TRADEABLE_SUPPLY;
    }

    function getVolume() public view returns (uint256) {
        return volume;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function getRewardDestination(address token) public view returns (uint32) {
        return rewardDestinations[token];
    }

    function getRewards() public view returns (address[] memory) {
        return rewards.keys();
    }

    function amountGreaterThanThreshold(uint256 amount) external pure returns (bool) {
        return amount > TRADEABLE_SUPPLY;
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        UD60x18 currentSupply = ud(getTokensHeldInCurve());
        UD60x18 newSupply = ud(getTokensHeldInCurve()).add(ud(amount));

        return ud(K).mul(newSupply.powu(2).sub(currentSupply.powu(2))).div(ud(2e18)).unwrap();
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        UD60x18 currentSupply = ud(getTokensHeldInCurve());
        UD60x18 newSupply = ud(getTokensHeldInCurve()).sub(ud(amount));

        return ud(K).mul(currentSupply.powu(2).sub(newSupply.powu(2))).div(ud(2e18)).unwrap();
    }

    function getAmountByETHSell(uint256 eth, uint256 maxSlippage) external view returns (uint256) {
        uint256 lower = 0;
        uint256 upper = getTokensHeldInCurve();
        while (getSellPrice(upper) < eth) {
            lower = upper - (upper / 10);
            upper *= 2;
        }

        return findTokenAmountForSell(eth, maxSlippage, lower, upper);
    }

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
            finalPrice <= receivedEther && (receivedEther - finalPrice) * 100 <= maxSlippage * finalPrice,
            "Slippage too high"
        );
        return lower;
    }

    function getAmountByETHBuy(uint256 eth, uint256 maxSlippage) external view returns (uint256) {
        uint256 lower = 0;
        uint256 upper = 1;
        while (getBuyPrice(upper) < eth) {
            lower = upper - (upper / 10);
            upper *= 2;
        }

        return findTokenAmountForBuy(eth, maxSlippage, lower, upper);
    }
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
            finalPrice <= paidEther && (paidEther - finalPrice) * 100 <= maxSlippage * finalPrice,
            "Slippage too high"
        );
        return lower;
    }

    function buy(uint256 amount, uint256 maxSlippage) external payable whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        if (amount + getTokensHeldInCurve() >= TRADEABLE_SUPPLY) {
            _pause();

            address pool = IUniswapV3Factory(uniswapFactory).createPool(address(this), WETH, poolFee);

            // Approve the Nonfungible Position Manager to spend tokens
            _approve(address(this), uniswapPositionManager, LIQUIDITY_POOL_AMOUNT);

            uint256 liquidity = address(this).balance - feesEarned;
            // Add liquidity
            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                token0: address(this),
                token1: WETH,
                fee: poolFee,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: LIQUIDITY_POOL_AMOUNT,
                amount1Desired: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                recipient: protocol(),
                deadline: block.timestamp
            });

            INonfungiblePositionManager(uniswapPositionManager).mint{ value: liquidity }(params);

            _transfer(address(this), owner(), creatorAmount);
            _transfer(address(this), pool, balanceOf(address(this)));

            // set the amount to whatever is extra than the threshold
            amount = amount - (getTokensHeldInCurve() - TRADEABLE_SUPPLY);
        }

        uint256 price = getBuyPrice(amount);
        uint256 fee = (price * buyFeePercent) / 100;

        if (msg.value >= price + fee) {
            uint256 refund = msg.value - price - fee;
            if (refund > 0) {
                payable(_msgSender()).sendValue(refund);
            }

            _buy(amount, price, fee);
        } else {
            uint256 actualAmount = findTokenAmountForBuy(
                msg.value - (msg.value * buyFeePercent) / 100,
                maxSlippage,
                amount < 10 ? 0 : amount / 10,
                amount * 4
            );
            require(actualAmount > 0, "Not enough input to buy the minimum amount of tokens");
            price = getBuyPrice(actualAmount);
            fee = (price * buyFeePercent) / 100;
            uint256 refund = msg.value - price - fee;
            if (refund > 0) {
                payable(_msgSender()).sendValue(refund);
            }

            _buy(actualAmount, price, fee);
        }
    }

    function _buy(uint256 amount, uint256 price, uint256 fee) internal {
        (, uint256 cur) = curveHoldings.tryGet(_msgSender());
        curveHoldings.set(_msgSender(), cur + amount);

        feesEarned += fee;
        purchaseRecords[_msgSender()].totalInvested = purchaseRecords[_msgSender()].totalInvested.add(ud(price));
        purchaseRecords[_msgSender()].totalTokensPurchased = purchaseRecords[_msgSender()].totalTokensPurchased.add(
            ud(amount)
        );
        _transfer(address(this), _msgSender(), amount);
        volume += msg.value;
        emit Buy(_msgSender(), getTokensHeldInCurve(), getBuyPrice(1e18), amount, price);
    }

    function sell(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        _sell(amount);
    }

    function _sell(uint256 amount) internal {
        uint256 balance = curveHoldings.get(_msgSender());
        require(balance >= amount, "Insufficient balance");
        if (balance - amount == 0) {
            curveHoldings.remove(_msgSender());
        } else {
            curveHoldings.set(_msgSender(), balance - amount);
        }

        uint256 price = getSellPrice(amount);

        console.log("Price for sell: %d", price);

        PurchaseData storage data = purchaseRecords[_msgSender()];

        UD60x18 averagePurchasePrice = data.totalInvested.div(data.totalTokensPurchased);

        UD60x18 originalInvestmentValue = ud(amount).mul(averagePurchasePrice);

        UD60x18 profitPercent = (ud(price).gt(originalInvestmentValue))
            ? ((ud(price).sub(originalInvestmentValue)).mul(ud(100))).div(originalInvestmentValue)
            : ud(0);

        UD60x18 sellFeePercent;
        if (profitPercent.lte(noFeeProfitPercent)) {
            sellFeePercent = ud(0);
        } else if (profitPercent.gte(fullFeeProfitPercent)) {
            sellFeePercent = maxSellFeePercent;
        } else {
            sellFeePercent = ((profitPercent.sub(noFeeProfitPercent)).mul(maxSellFeePercent)).div(
                (fullFeeProfitPercent.sub(noFeeProfitPercent))
            );
        }
        uint256 fee = (ud(price).mul(sellFeePercent)).div(ud(100)).unwrap();

        payable(_msgSender()).sendValue(price - fee);

        volume += price;

        feesEarned += fee;

        _transfer(_msgSender(), address(this), amount);

        emit Sell(_msgSender(), getTokensHeldInCurve(), getBuyPrice(1e18), amount, price);
    }

    function testWithdrawRemoveBeforeProd() public onlyOwner {
        payable(_msgSender()).sendValue(address(this).balance);
    }

    function claimFees() public onlyOwner {
        // protocol fee percent
        uint256 protocolFee = (feesEarned * protocolFeePercent) / 100;
        feesEarned -= protocolFee;
        protocol().sendValue(protocolFee);

        // creator fee percent
        uint256 creatorFee = (feesEarned * creatorFeePercent) / 100;
        feesEarned -= creatorFee;
        payable(owner()).sendValue(creatorFee);
    }

    function sponsor(address token, uint256 amount) public payable {
        require(IERC20(token).allowance(_msgSender(), address(this)) >= amount, "Allowance not set");
        IERC20(token).transferFrom(_msgSender(), address(this), amount);
        (, uint256 cur) = rewards.tryGet(token);
        rewards.set(token, cur + amount);
        sponsors[_msgSender()][token] += amount;
    }

    function unsponsor(address token, uint256 amount) public payable {
        uint256 cur = sponsors[_msgSender()][token];
        require(cur >= amount, "Insufficient sponsorship");
        sponsors[_msgSender()][token] -= amount;
        rewards.set(token, rewards.get(token) - amount);
        IERC20(token).transfer(_msgSender(), amount);
    }

    function buildRewardsClaimMessage(address token, uint256 amount) public view returns (bytes memory) {
        return abi.encode(token, amount, _msgSender());
    }

    function quoteRewardsClaim(address token, uint128 executorGasLimit) public view returns (MessagingFee memory fee) {
        uint256 curveHolding = curveHoldings.get(_msgSender());
        uint256 totalRewards = rewards.get(token);
        uint256 rewardAmount = (totalRewards * curveHolding) / getTokensHeldInCurve();
        bytes memory payload = buildRewardsClaimMessage(token, rewardAmount);
        uint32 destEid = rewardDestinations[token];
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);
        fee = _quote(destEid, payload, options, false);
    }

    function claimRewards(address token, uint128 executorGasLimit) public payable whenPaused {
        require(!rewardClaims[_msgSender()][token], "Already claimed");

        uint256 curveHolding = curveHoldings.get(_msgSender());
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);

        uint256 totalRewards = rewards.get(token);
        uint256 rewardAmount = (totalRewards * curveHolding) / getTokensHeldInCurve();

        uint32 destEid = rewardDestinations[token];
        if (destEid == 0 || destEid == endpoint.eid()) {
            IERC20(token).transfer(_msgSender(), rewardAmount);
        } else {
            bytes memory message = buildRewardsClaimMessage(token, rewardAmount);
            _lzSend(destEid, message, options, MessagingFee(msg.value, 0), payable(msg.sender));
        }
        rewardClaims[_msgSender()][token] = true;
    }

    function protocol() public view returns (address payable) {
        return payable(Ownable(address(streamz)).owner());
    }

    // override transfer and transferFrom to modify curveHoldings
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (!paused()) {
            uint256 balance = curveHoldings.get(_msgSender());
            require(balance >= amount, "Insufficient balance");
            if (balance - amount == 0) {
                curveHoldings.remove(_msgSender());
            } else {
                curveHoldings.set(_msgSender(), balance - amount);
            }
            // update recipient balance
            (, uint256 recBalance) = curveHoldings.tryGet(recipient);
            curveHoldings.set(recipient, recBalance + amount);
        }
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (!paused()) {
            uint256 balance = curveHoldings.get(sender);
            require(balance >= amount, "Insufficient balance");
            if (balance - amount == 0) {
                curveHoldings.remove(sender);
            } else {
                curveHoldings.set(sender, balance - amount);
            }
            // update recipient balance
            (, uint256 recBalance) = curveHoldings.tryGet(recipient);
            curveHoldings.set(recipient, recBalance + amount);
        }
        return super.transferFrom(sender, recipient, amount);
    }

    //  abi.encode(endpoint.eid(), token, amount, _msgSender());

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (uint32 destEid, address token, uint256 amount) = abi.decode(payload, (uint32, address, uint256));
        rewards.set(token, amount);
        rewardDestinations[token] = destEid;
    }
}
