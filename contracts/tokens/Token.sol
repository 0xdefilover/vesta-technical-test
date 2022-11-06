// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Callback } from "./ERC20Callback.sol";

contract Token is ERC20Callback, Ownable {
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20Callback(_name, _symbol) {}

    function mint(address _to, uint256 _amount) public onlyOwner {
        require(_amount > 0, "Invalid amount");
        _mint(_to, _amount);
    }
}
