// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./BSCTestV4.sol";

contract BSCTestV5 is BSCTestV4 {
    function initializeV5() external reinitializer(5) {
        if (block.chainid != 97) revert ChainIdMismatch();
    }
}