// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IDeHolder.sol";
// import "./IERC20.sol";

contract DeHolder is IDeHolder{

	address fundContract;

	constructor (address _fundContract) {
        fundContract = _fundContract;
    }

	function _buy (address token, address to) override external payable
	{
        require(msg.sender == fundContract, "Illegal request");
		IERC20(token).transfer(to, msg.value*2);
	}
}