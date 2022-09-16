// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./BSCTestV3.sol";

contract BSCTestV4 is BSCTestV3 {
    function initializeV4() external reinitializer(4) {
        if (block.chainid != 97) revert ChainIdMismatch();
    }
}
