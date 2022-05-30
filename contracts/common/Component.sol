// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./errors.sol";

abstract contract Component {
    address private immutable _deployer;
    address private _coreContract;

    event CoreContractSet(address);

    modifier onlyCoreContract() {
        if (msg.sender != _coreContract) revert NotCalledByCoreContract();
        _;
    }

    modifier coreContractValid() {
        if (_coreContract == address(0)) revert CoreContractNotSet();
        _;
    }

    constructor() {
        _deployer = msg.sender;
    }

    function setCoreContract(address core) external {
        if (core == address(0)) revert InvalidCoreContract();
        if (msg.sender != _deployer) revert NotCalledByDeployer();
        if (_coreContract != address(0)) revert CoreContractAreadySet();
        _coreContract = core;
        emit CoreContractSet(_coreContract);
    }

    function deployer() public view returns (address) {
        return _deployer;
    }

    function coreContract() public view returns (address) {
        return _coreContract;
    }
}