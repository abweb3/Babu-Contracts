// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract LiquidityLocker is IERC721Receiver {
    address public owner;
    uint256 public unlockTime;

    INonfungiblePositionManager public positionManager;
    IERC20 public babuToken;
    uint256 public lastClaimTime;
    uint256 public claimInterval;

    mapping(address => uint256) public babuBalances; // Track BABU token balances

    constructor(
        uint256 _unlockTime,
        address _positionManager,
        address _babuToken,
        uint256 _claimInterval
    ) {
        owner = msg.sender;
        unlockTime = _unlockTime;
        positionManager = INonfungiblePositionManager(_positionManager);
        babuToken = IERC20(_babuToken);
        claimInterval = _claimInterval;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        require(block.timestamp >= unlockTime, "Too soon to receive liquidity tokens.");
        require(msg.sender == address(positionManager), "Tokens must be sent by position manager.");
        require(operator == owner, "Tokens can only be received by contract owner.");

        return this.onERC721Received.selector;
    }

    function claimFees(uint256 tokenId) external {
        require(msg.sender == owner, "Only owner can claim fees.");
        require(block.timestamp >= lastClaimTime + claimInterval, "Too soon to claim fees again.");

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);

        require(liquidity > 0, "No liquidity in position.");

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 fees0, uint256 fees1) = positionManager.collect(params);

        lastClaimTime = block.timestamp;

        // Distribute the fees to BABU token holders here.
        uint256 totalSupply = babuToken.totalSupply();
        for (uint i = 0; i < totalSupply; i++) {
            address holder = babuToken.tokenOfOwnerByIndex(i);
            uint256 balance = babuToken.balanceOf(holder);
            uint256 fees = (balance * fees0) / totalSupply; // Distribute based on BABU token balance
            babuBalances[holder] += fees;
        }
    }
}
