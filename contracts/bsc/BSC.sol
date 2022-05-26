// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../common/Core.sol";

contract BSC is Core {
    function initialize() public virtual override initializer {
        __Core_init();
    }

    function normalizedChainId() public view virtual override returns (uint32) {
        return 4;
    }
}
