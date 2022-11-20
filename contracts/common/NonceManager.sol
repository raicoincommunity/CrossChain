// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./errors.sol";

contract NonceManager {
    uint256 private _nonce;

    modifier useNonce(uint256 nonce) {
        if (nonce != _nonce) revert NonceMismatch();
        unchecked {
            ++_nonce;
        }
        _;
    }

    function getNonce() public view returns (uint256) {
        return _nonce;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
