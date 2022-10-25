// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20Callback.sol";

contract Token is ERC20Callback {
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20Callback(_name, _symbol) {}
}
