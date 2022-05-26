pragma solidity ^0.8.4;

import "../common/Core.sol";

contract ETH is Core {
    function initialize() public virtual override initializer {
        __Core_init();
    }

    function normalizedChainId() public view virtual override returns (uint32) {
        return 3;
    }
}
