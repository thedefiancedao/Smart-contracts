// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDeHolder {
	function _buy (address token, address to, uint256 amount) external payable;
}