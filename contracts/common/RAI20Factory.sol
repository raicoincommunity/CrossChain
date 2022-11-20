// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Component.sol";
import "./errors.sol";

contract RAI20 is ERC20, Initializable {
    uint8 private _decimals;
    uint32 private _originalChainId;
    bytes32 private _originalContract;
    address private _coreContract;

    string private _originalChain;
    string private _name;
    string private _symbol;

    constructor() ERC20("", "") {
        _disableInitializers();
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        string calldata originalChain_,
        uint32 originalChainId_,
        bytes32 originalContract_,
        uint8 decimals_,
        address coreContract_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _originalChain = originalChain_;
        _originalChainId = originalChainId_;
        _originalContract = originalContract_;
        _decimals = decimals_;
        _coreContract = coreContract_;
    }

    modifier onlyCoreContract() {
        if (_msgSender() != _coreContract) revert NotCalledByCoreContract();
        _;
    }

    function mint(address to, uint256 amount) external onlyCoreContract {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyCoreContract {
        _burn(_msgSender(), amount);
    }

    function originalChain() external view returns (string memory) {
        return _originalChain;
    }

    function originalChainId() external view returns (uint32) {
        return _originalChainId;
    }

    function originalContract() external view returns (bytes32) {
        return _originalContract;
    }

    function coreContract() external view returns (address) {
        return _coreContract;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract RAI20Factory is Component {
    address private immutable _implementation;

    event TokenCreated(address);

    constructor() {
        _implementation = address(new RAI20());
    }

    function create(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract,
        uint8 decimals
    ) external onlyCoreContract returns (address addr) {
        addr = Clones.cloneDeterministic(
            _implementation,
            calcSalt(originalChainId, originalContract)
        );
        if (addr == address(0)) revert CreateWrappedTokenFailed();
        RAI20(addr).initialize(
            name,
            symbol,
            originalChain,
            originalChainId,
            originalContract,
            decimals,
            coreContract()
        );
        emit TokenCreated(addr);
        return addr;
    }

    function calcSalt(uint32 originalChainId, bytes32 originalContract)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(originalChainId, originalContract));
    }
}
