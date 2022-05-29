// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

abstract contract Component {
    address private immutable _deployer;
    address private _coreContract;

    event CoreContractSet(address);

    modifier onlyCoreContract() {
        require(msg.sender == _coreContract, "not from core");
        _;
    }

    modifier coreContractValid() {
        require(_coreContract != address(0), "core not set");
        _;
    }

    constructor() {
        _deployer = msg.sender;
    }

    function setCoreContract(address core) external {
        require(core != address(0), "invalid address");
        require(msg.sender == _deployer, "not deployer");
        require(_coreContract == address(0), "already set");
        _coreContract = core;
        emit CoreContractSet(_coreContract);
    }

    function deployer () public view returns (address) {
        return _deployer;
    }

    function coreContract() public view returns (address) {
        return _coreContract;
    }
}