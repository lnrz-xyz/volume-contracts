// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OAppReceiver, OAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract RewardsDistributor is OApp {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using OptionsBuilder for bytes;

    uint32 public destEid;

    constructor(address _endpoint, uint32) OApp(_endpoint, msg.sender) Ownable(msg.sender) {}

    EnumerableMap.AddressToUintMap private rewards;
    mapping(address => mapping(address => uint256)) private sponsors;

    function buildSponsorMessage(address token, uint256 amount) public view returns (bytes memory) {
        return abi.encode(endpoint.eid(), token, amount);
    }

    function quoteSponsor(
        address token,
        uint256 amount,
        uint128 executorGasLimit
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = buildSponsorMessage(token, amount);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);
        fee = _quote(destEid, payload, options, false);
    }

    function sponsor(address token, uint256 amount, uint128 executorGasLimit) public payable {
        require(IERC20(token).allowance(_msgSender(), address(this)) >= amount, "Allowance not set");
        IERC20(token).transferFrom(_msgSender(), address(this), amount);
        (, uint256 cur) = rewards.tryGet(token);
        rewards.set(token, cur + amount);
        sponsors[_msgSender()][token] += amount;

        bytes memory payload = buildSponsorMessage(token, rewards.get(token));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);
        _lzSend(destEid, payload, options, MessagingFee(msg.value, 0), payable(address(this)));
    }

    function unsponsor(address token, uint256 amount, uint128 executorGasLimit) public payable {
        uint256 cur = sponsors[_msgSender()][token];
        require(cur >= amount, "Insufficient sponsorship");
        sponsors[_msgSender()][token] -= amount;
        rewards.set(token, rewards.get(token) - amount);
        IERC20(token).transfer(_msgSender(), amount);

        bytes memory payload = buildSponsorMessage(token, rewards.get(token));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(executorGasLimit, 0);
        _lzSend(destEid, payload, options, MessagingFee(msg.value, 0), payable(address(this)));
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (address token, uint256 amount, address to) = abi.decode(payload, (address, uint256, address));
        IERC20(token).transfer(to, amount);
    }
}
