//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;
import "./DePlayground.sol";

contract DeSecurity {
    uint256 public balanceOfContract;
    DePlayground auction;
    uint256 tokenID;
    address erc20;
    uint256 amount;
    bool reverts;
    bool withdrawFail;

    function setAuctionContract(address _auctionContract) external {
        auction = DePlayground(_auctionContract);
    }

    function bidOnAuction(
        address _erc20,
        uint256 _token,
        uint256 _amount
    ) external {
        auction.makeBid{value: _amount}(_erc20, _token, address(0), 0);
        erc20 = _erc20;
        tokenID = _token;
        amount = _amount;
        balanceOfContract -= _amount;
    }

    function setRequire(bool _req) external {
        reverts = _req;
    }

    function withdraw() public {
        auction.withdrawBid(erc20, tokenID);
    }

    function deposit() external payable {
        balanceOfContract += msg.value;
    }

    function withdrawFailed() external payable {
        withdrawFail = true;
        auction.withdrawAllFailedCredits();
    }

    receive() external payable {
        balanceOfContract += msg.value;
        require(reverts, "Cause failure to block next bidder");
        if (!withdrawFail) {
            withdraw(); //attempt to withdraw again
        }
    }
}