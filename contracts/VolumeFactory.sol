// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./VolumeToken.sol";
import "./VolumeConfiguration.sol";

contract VolumeFactory is Ownable {
    uint256 public deploymentFee;
    address public feeRecipient;
    uint256 public accumulatedFees;

    VolumeConfiguration public immutable config;

    event VolumeTokenCreated(
        address indexed creator,
        address indexed tokenAddress
    );

    constructor(
        uint256 _initialFee,
        address _uniswapFactory,
        address _uniswapPositionManager,
        address _weth,
        address _splitFactory
    ) Ownable(msg.sender) {
        deploymentFee = _initialFee;
        feeRecipient = msg.sender;

        config = new VolumeConfiguration(
            msg.sender,
            _uniswapFactory,
            _uniswapPositionManager,
            _weth,
            _splitFactory
        );
    }

    function createVolumeToken(
        string memory name,
        string memory symbol,
        string memory uri
    ) external payable returns (address) {
        require(msg.value >= deploymentFee, "Insufficient fee");
        require(msg.value - deploymentFee <= 0.25 ether, "Max 0.25 ETH");

        VolumeToken newToken = new VolumeToken(
            address(config),
            name,
            symbol,
            uri,
            msg.sender
        );

        accumulatedFees += deploymentFee;

        if (msg.value > deploymentFee) {
            // send back the rest
            payable(msg.sender).transfer(msg.value - deploymentFee);
        }

        emit VolumeTokenCreated(msg.sender, address(newToken));
        return address(newToken);
    }

    function distributeFees() external {
        uint256 feesToDistribute = accumulatedFees;
        accumulatedFees = 0;
        payable(feeRecipient).transfer(feesToDistribute);
    }

    function updateDeploymentFee(uint256 _newFee) external onlyOwner {
        deploymentFee = _newFee;
    }

    function updateFeeRecipient(address _newRecipient) external onlyOwner {
        feeRecipient = _newRecipient;
    }
}
