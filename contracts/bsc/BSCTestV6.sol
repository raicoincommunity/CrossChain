// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./BSCTest.sol";

contract BSCTestV6 is BSCTest {
    function initializeV6() external reinitializer(6) {
        if (block.chainid != 97) revert ChainIdMismatch();
    }
}
