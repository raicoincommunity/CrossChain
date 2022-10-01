// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./Goerli.sol";

contract GoerliV3 is Goerli {
    function initializeV3() external reinitializer(3) {
        if (block.chainid != 5) revert ChainIdMismatch();
    }
}
