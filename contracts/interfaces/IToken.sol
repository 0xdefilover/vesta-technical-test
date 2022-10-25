// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IToken {
    function transfer(
        address to, 
        uint256 amount
    ) external returns (bool);

    function transferFrom(
		address from,
		address to,
		uint256 amount
	) external returns (bool);
}
