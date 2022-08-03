// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./errors.sol";

contract NonceManager {
    uint256 private _nonce;

    modifier useNonce(uint256 nonce) {
        if (nonce != _nonce) revert NonceMismatch();
        nonce++;
        _;
    }

    function getNonce() public view returns (uint256) {
        return _nonce;
    }
}
