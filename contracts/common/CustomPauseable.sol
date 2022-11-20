// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./CustomEIP712Upgradeable.sol";
import "./NonceManager.sol";
import "./Verifier.sol";
import "./errors.sol";

contract CustomPausable is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    CustomEIP712Upgradeable,
    NonceManager,
    Verifier
{
    bytes32 private constant _PAUSE_TYPEHASH = keccak256("Pause(uint256 nonce)");
    bytes32 private constant _UNPAUSE_TYPEHASH = keccak256("Unpause(uint256 nonce)");

    function pause(uint256 nonce, bytes calldata signatures)
        external
        whenNotPaused
        useNonce(nonce)
    {
        bytes32 structHash = keccak256(abi.encode(_PAUSE_TYPEHASH, nonce));
        if (!verify(structHash, signatures)) revert VerificationFailed();

        _pause();
    }

    function unpause(uint256 nonce, bytes calldata signatures)
        external
        whenPaused
        useNonce(nonce)
    {
        bytes32 structHash = keccak256(abi.encode(_UNPAUSE_TYPEHASH, nonce));
        if (!verify(structHash, signatures)) revert VerificationFailed();

        _unpause();
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
