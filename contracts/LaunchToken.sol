// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./INonfungiblePositionManager.sol";
import "hardhat/console.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract LaunchToken is ERC20, ERC20Permit, Ownable, Pausable, OApp {
    using OptionsBuilder for bytes;
    using Address for address payable;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    IERC20 public constant streamz = IERC20(0x499A12387357e3eC8FAcc011A2AB662e8aBdBd8f);

    // total erc20 supply
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    // the amount that will be tradeable before we pause the contract and create a uniswap pool
    uint256 public constant TRADEABLE_SUPPLY = 200_000_000 * 1e18;

    // constant K for bonding curve calculation
    uint256 public constant K = (8 * 1e18) / (200000000 ** 2);

    // the amount we match for liquidity when creating the pool
    uint256 public constant LIQUIDITY_POOL_AMOUNT = 200_000_000 * 1e18;

    // max creator amount
    uint256 public constant CREATOR_MAX_BUY = 10_000_000 * 1e18;
    // amount to burn after pool creation
    uint256 public constant BURN_AMOUNT = 200_000_000 * 1e18;

    // pool fee tier (1%)
    uint24 public constant POOL_FEE = 10000;
    // the fee percent for buying tokens
    uint256 public buyFeePercent = 10;

    // how much of the fees go to the protocol vs the creator
    uint256 public protocolFeePercent = 30;
    uint256 public creatorFeePercent = 70;

    address private immutable uniswapRouter;
    address private immutable uniswapFactory;
    INonfungiblePositionManager private immutable uniswapPositionManager;
    address private immutable WETH;

    event Buy(address indexed trader, uint256 newSupply, uint256 newBuyPrice, uint256 amount, uint256 ethAmount);

    event Sell(address indexed trader, uint256 newSupply, uint256 newBuyPrice, uint256 amount, uint256 ethAmount);

    event CurveEnded(address indexed pool, uint128 liquidity, uint256 tokenId);

    event RewardsClaimed(address indexed holder, address indexed token, uint256 amount, uint32 destination);

    // holder -> amount
    EnumerableMap.AddressToUintMap private curveHoldings;

    // token address -> amount
    EnumerableMap.AddressToUintMap private rewards;
    // token address -> LayerZero endpoint id
    mapping(address => uint32) private rewardDestinations;
    // holder -> token address -> claimed
    mapping(address => mapping(address => bool)) private rewardClaims;
    // sponsor -> token address -> amount
    mapping(address => mapping(address => uint256)) private sponsors;

    uint256 private volume;

    uint256 private feesEarned;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    // uniswap deposits
    mapping(uint256 => Deposit) public deposits;

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
        uniswapPositionManager = INonfungiblePositionManager(_positions);
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

    function getReward(address token) public view returns (uint256) {
        return rewards.get(token);
    }

    function getRewardIsClaimed(address holder, address token) public view returns (bool) {
        return rewardClaims[holder][token];
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
            finalPrice <= paidEther && (paidEther - finalPrice) * 100 <= maxSlippage * finalPrice,
            "Slippage too high"
        );
        return lower;
    }

    function buy(uint256 amount, uint256 maxSlippage) external payable whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        if (_msgSender() != owner()) {
            require(balanceOf(_msgSender()) + amount <= CREATOR_MAX_BUY, "Amount exceeds max buy for creator");
        }

        if (amount + getTokensHeldInCurve() >= TRADEABLE_SUPPLY) {
            // curve ends here

            _pause();

            // create the pool
            address pool = IUniswapV3Factory(uniswapFactory).createPool(address(this), WETH, POOL_FEE);

            // Approve the Nonfungible Position Manager to spend tokens
            _approve(address(this), address(uniswapPositionManager), LIQUIDITY_POOL_AMOUNT);

            uint256 liquidity = address(this).balance - feesEarned;
            // Add liquidity
            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                token0: address(this),
                token1: WETH,
                fee: POOL_FEE,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: LIQUIDITY_POOL_AMOUNT,
                amount1Desired: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                recipient: protocol(),
                deadline: block.timestamp
            });

            (uint256 tokenId, uint128 liquidityAdded, , uint256 amount1) = uniswapPositionManager.mint{
                value: liquidity
            }(params);

            // if the amount1 (eth) is less than the liquidity, send the diff to the protocol
            if (amount1 < liquidity) {
                payable(protocol()).sendValue(liquidity - amount1);
            }

            _burn(address(this), BURN_AMOUNT);
            _transfer(address(this), pool, balanceOf(address(this)) - amount);

            emit CurveEnded(pool, liquidityAdded, tokenId);
            // still finish this transaction
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
        volume += msg.value;

        _transfer(address(this), _msgSender(), amount);
        emit Buy(_msgSender(), getTokensHeldInCurve(), getBuyPrice(1e18), amount, price);
    }

    // maybe add slippage and desired sale price to sell, or a separate function for this
    function sell(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        uint256 balance = curveHoldings.get(_msgSender());
        require(balance >= amount, "Insufficient balance");
        if (balance - amount == 0) {
            curveHoldings.remove(_msgSender());
        } else {
            curveHoldings.set(_msgSender(), balance - amount);
        }

        uint256 price = getSellPrice(amount);

        payable(_msgSender()).sendValue(price);

        volume += price;

        _transfer(_msgSender(), address(this), amount);

        emit Sell(_msgSender(), getTokensHeldInCurve(), getBuyPrice(1e18), amount, price);
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
        protocol().sendValue(protocolFee);
    }

    // sponsor rewards on the deployed chain of this contract
    function sponsor(address token, uint256 amount) public payable whenNotPaused {
        require(IERC20(token).allowance(_msgSender(), address(this)) >= amount, "Allowance not set");
        IERC20(token).transferFrom(_msgSender(), address(this), amount);
        (, uint256 cur) = rewards.tryGet(token);
        rewards.set(token, cur + amount);
        sponsors[_msgSender()][token] += amount;
    }

    // unsponsor rewards on the deployed chain of this contract
    function unsponsor(address token) public payable whenNotPaused {
        uint256 cur = sponsors[_msgSender()][token];
        delete sponsors[_msgSender()][token];
        rewards.set(token, rewards.get(token) - cur);
        IERC20(token).transfer(_msgSender(), cur);
    }

    // this is the message that will be sent to a rewards holdings contract on another chain
    function buildRewardsClaimMessage(address token, uint256 amount) public view returns (bytes memory) {
        return abi.encode(token, amount, _msgSender());
    }

    // TODO what is a reasonable input for the executorGasLimit?
    // this is the fee it will cost to send the cross chain message that should be sent along with any function that claims rewards
    function quoteRewardsClaim(address token, uint128 executorGasLimit) public view returns (MessagingFee memory fee) {
        uint256 curveHolding = curveHoldings.get(_msgSender());
        uint256 totalRewards = rewards.get(token);
        uint256 rewardAmount = (totalRewards * curveHolding) / getTokensHeldInCurve();
        bytes memory payload = buildRewardsClaimMessage(token, rewardAmount);
        uint32 destEid = rewardDestinations[token];
        if (destEid == 0 || destEid == endpoint.eid()) {
            return MessagingFee(0, 0);
        }
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);
        fee = _quote(destEid, payload, options, false);
    }

    // claims rewards post game
    function claimRewards(address token, uint128 executorGasLimit) public payable whenPaused {
        require(!rewardClaims[_msgSender()][token], "Already claimed");

        uint256 curveHolding = curveHoldings.get(_msgSender());

        uint256 totalRewards = rewards.get(token);
        uint256 rewardAmount = (totalRewards * curveHolding) / getTokensHeldInCurve();
        uint32 destEid = rewardDestinations[token];
        // if the destination is the same chain, just transfer the rewards
        // if the destination is an alternate chain, use layer zero to trigger the rewards claim
        if (destEid == 0 || destEid == endpoint.eid()) {
            IERC20(token).transfer(_msgSender(), rewardAmount);
        } else {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);
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

    // this will be called when a reward is added on another chain and is used to update the rewards mapping to account for the rewards
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
