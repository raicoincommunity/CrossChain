// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./Component.sol";
import "./errors.sol";

contract RAI721 is ERC721, ERC721Enumerable, Initializable {
    uint32 private _originalChainId;
    bytes32 private _originalContract;
    address private _coreContract;

    string private _originalChain;
    string private _name;
    string private _symbol;

    constructor() ERC721("", "") {
        _disableInitializers();
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        string calldata originalChain_,
        uint32 originalChainId_,
        bytes32 originalContract_,
        address coreContract_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _originalChain = originalChain_;
        _originalChainId = originalChainId_;
        _originalContract = originalContract_;
        _coreContract = coreContract_;
    }

    modifier onlyCoreContract() {
        if (_msgSender() != _coreContract) revert NotCalledByCoreContract();
        _;
    }

    function mint(address to, uint256 tokenId) external onlyCoreContract {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyCoreContract {
        if (ownerOf(tokenId) != _msgSender()) revert TokenIdNotOwned();
        _burn(tokenId);
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

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract RAI721Factory is Component {
    address private immutable _implementation;

    event TokenCreated(address);

    constructor() {
        _implementation = address(new RAI721());
    }

    function create(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract
    ) external onlyCoreContract returns (address addr) {
        addr = Clones.cloneDeterministic(
            _implementation,
            calcSalt(originalChainId, originalContract)
        );
        if (addr == address(0)) revert CreateWrappedTokenFailed();
        RAI721(addr).initialize(
            name,
            symbol,
            originalChain,
            originalChainId,
            originalContract,
            coreContract()
        );
        emit TokenCreated(addr);
        return addr;
    }

    function implementation() external view returns (address) {
        return _implementation;
    }

    function calcSalt(uint32 originalChainId, bytes32 originalContract)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(originalChainId, originalContract));
    }
}
