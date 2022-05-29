// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import "./CustomEIP712Upgradeable.sol";
import "./NonceManager.sol";
import "./Verifier.sol";
import "./CustomPauseable.sol";
import "./IRAI20Factory.sol";
import "./IRAI721Factory.sol";
import "./IValidatorManager.sol";

interface IDecimals {
    function decimals() external view returns (uint8);
}

abstract contract Core is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ERC721HolderUpgradeable,
    CustomEIP712Upgradeable,
    NonceManager,
    Verifier,
    CustomPausable
{
    /*=========================== 1. STRUCTS =================================*/
    enum TokenType {
        INVALID,
        ERC20,
        ERC721
    }

    struct TokenInfo {
        uint256 reserve;
        TokenType tokenType;
        bool versatile; // the balance is subject to external changes, e.g.
        bool wrapped;
        bool initialized;
        uint8 decimals;
    }

    /*=========================== 2. CONSTANTS ===============================*/
    bytes32 private constant _UPGRADE_TYPEHASH =
        keccak256("Upgrade(address newImplementation,uint256 nonce)");
    bytes32 private constant _UNMAP_ERC20_TYPEHASH =
        keccak256(
            "UnmapERC20(IERC20Upgradeable token,bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 share)"
        );
    bytes32 private constant _UNMAP_ETH_TYPEHASH =
        keccak256(
            "UnmapETH(bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 amount)"
        );
    bytes32 private constant _UNMAP_ERC721_TYPEHASH =
        keccak256(
            "UnmapERC721(IERC721Upgradeable token,bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 tokenId)"
        );
    bytes32 private constant _CREATE_WRAPPED_ERC20_TOKEN_TYPEHASH =
        keccak256(
            "CreateWrappedERC20Token(string name,string symbol,string originalChain,uint32 originalChainId,bytes32 originalContract,uint8 decimals)"
        );
    bytes32 private constant _CREATE_WRAPPED_ERC721_TOKEN_TYPEHASH =
        keccak256(
            "CreateWrappedERC721Token(string name,string symbol,string originalChain,uint32 originalChainId,bytes32 originalContract)"
        );
    bytes32 private constant _WRAP_ERC20_TOKEN_TYPEHASH =
        keccak256(
            "WrapERC20Token(uint32 originalChainId,bytes32 originalContract,bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 amount)"
        );
    bytes32 private constant _WRAP_ERC721_TOKEN_TYPEHASH =
        keccak256(
            "WrapERC721Token(uint32 originalChainId,bytes32 originalContract,bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 tokenId)"
        );

    /*=========================== 3. STATE VARIABLES =========================*/
    IRAI20Factory private _rai20Factory;
    IRAI721Factory private _rai721Factory;
    address private _newImplementation;
    uint256 private _ethReserve;
    mapping(address => TokenInfo) private _tokenInfos;
    // mapping token ID to block height at which the token was received
    mapping(IERC721Upgradeable => mapping(uint256 => uint256)) private _tokenIdReserve;
    // mapping unmap transaction hash to block height at which the unmap was executed
    // it is used to prevent double-spending of unmap transactions
    mapping(bytes32 => uint256) _unmappedTxns;
    // maping original (chain, token address) to wrapped token address
    mapping(uint32 => mapping(bytes32 => address)) _wrappedTokens;

    /*=========================== 4. EVENTS ==================================*/
    event NewImplementationSet(address newImplementation);
    event TokenInfoInitialized(
        address indexed token,
        TokenType tokenType,
        bool wrapped,
        uint8 decimals,
        uint32 normalizedChainId
    );

    event ERC20TokenMapped(
        address indexed token,
        address indexed sender,
        bytes32 indexed recipient,
        uint256 amount,
        uint256 share,
        uint32 normalizedChainId
    );

    event ETHMapped(
        address indexed sender,
        bytes32 indexed recipient,
        uint256 amount,
        uint32 normalizedChainId
    );

    event ERC721TokenMapped(
        address indexed token,
        address indexed sender,
        bytes32 indexed recipient,
        uint256 tokenId,
        uint32 normalizedChainId
    );

    event ERC20TokenUnmapped(
        address indexed token,
        bytes32 indexed sender,
        address indexed recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 amount,
        uint256 share,
        uint32 normalizedChainId
    );

    event ETHUnmapped(
        bytes32 indexed sender,
        address indexed recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 amount,
        uint32 normalizedChainId
    );

    event ERC721TokenUnmapped(
        address indexed token,
        bytes32 indexed sender,
        address indexed recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 tokenId,
        uint32 normalizedChainId
    );

    event WrappedERC20TokenCreated(
        uint32 indexed originalChainId,
        bytes32 indexed originalContract,
        address indexed wrappedAddress,
        string name,
        string symbol,
        string originalChain,
        uint8 decimals,
        uint32 normalizedChainId
    );

    event WrappedERC721TokenCreated(
        uint32 indexed originalChainId,
        bytes32 indexed originalContract,
        address indexed wrappedAddress,
        string name,
        string symbol,
        string originalChain,
        uint32 normalizedChainId
    );

    event ERC20TokenWrapped(
        uint32 indexed originalChainId,
        bytes32 indexed originalContract,
        bytes32 indexed sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        address wrappedAddress,
        uint256 amount,
        uint32 normalizedChainId
    );

    event ERC721TokenWrapped(
        uint32 indexed originalChainId,
        bytes32 indexed originalContract,
        bytes32 indexed sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        address wrappedAddress,
        uint256 tokenId,
        uint32 normalizedChainId
    );

    event ERC20TokenUnwrapped(
        uint32 indexed originalChainId,
        bytes32 indexed originalContract,
        address indexed sender,
        bytes32 recipient,
        address wrappedAddress,
        uint256 amount,
        uint32 normalizedChainId
    );

    event ERC721TokenUnwrapped(
        uint32 indexed originalChainId,
        bytes32 indexed originalContract,
        address indexed sender,
        bytes32 recipient,
        address wrappedAddress,
        uint256 tokenId,
        uint32 normalizedChainId
    );

    /*=========================== 5. MODIFIERS ===============================*/

    /*=========================== 6. FUNCTIONS ===============================*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __Core_init(
        IValidatorManager validatorManager,
        IRAI20Factory rai20Factory,
        IRAI721Factory rai721Factory
    ) internal onlyInitializing {
        // todo: unchain_init
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ERC721Holder_init();
        __EIP712_init();
        __Verifier_init(validatorManager);
        __Core_init_unchained(rai20Factory, rai721Factory);
    }

    function __Core_init_unchained(IRAI20Factory rai20Factory, IRAI721Factory rai721Factory)
        internal
        onlyInitializing
    {
        _rai20Factory = rai20Factory;
        _rai721Factory = rai721Factory;
        // todo:
    }

    function upgrade(
        address impl,
        uint256 nonce,
        bytes calldata signatures
    ) external nonReentrant whenNotPaused useNonce(nonce) {
        bytes32 structHash = keccak256(abi.encode(_UPGRADE_TYPEHASH, impl, nonce));
        require(verify(structHash, signatures), "verify");
        require(impl != address(0) && impl != _getImplementation(), "impl");

        _newImplementation = impl;
        emit NewImplementationSet(impl);
    }

    /**
     * @dev As compatible with ERC165 is not required by ERC20, to eliminate the risk of
     * forging other tokens into ERC20, we enforce
     * 1）The token should support 'function decimals() external view returns (uint8)'
     * 2) The increasing amount of 'token.balanceOf[this]' should be greater than 1
     */
    function mapERC20(
        IERC20Upgradeable token,
        uint256 amount,
        bytes32 recipient
    ) external payable nonReentrant whenNotPaused chargeFee(msg.value) {
        require(address(token) != address(0), "token");
        require(amount > 0, "amount");
        require(recipient != bytes32(0), "recipient");

        TokenInfo memory info = _tokenInfos[address(token)];
        if (!info.initialized) {
            _initERC20(info, token, false);
        }
        require(info.tokenType == TokenType.ERC20, "type");
        require(!info.wrapped, "wrapped");

        uint256 balance = token.balanceOf(address(this));
        SafeERC20Upgradeable.safeTransferFrom(token, _msgSender(), address(this), amount);
        uint256 newBalance = token.balanceOf(address(this));
        require(newBalance > balance + 1, "balance");

        uint256 share = newBalance - balance;
        if (info.versatile || info.reserve < balance) {
            share = (share * info.reserve) / balance;
        }
        require(share > 0, "share");
        info.reserve += share;
        _tokenInfos[address(token)] = info;
        emit ERC20TokenMapped(
            address(token),
            _msgSender(),
            recipient,
            amount,
            share,
            normalizedChainId()
        );
    }

    function mapETH(
        uint256 amount,
        bytes32 recipient,
        uint256 fee
    ) external payable nonReentrant whenNotPaused chargeFee(fee) {
        require(amount > 0, "amount");
        require(recipient != bytes32(0), "recipient");
        require(msg.value == amount + fee, "value");

        _ethReserve += amount;
        emit ETHMapped(_msgSender(), recipient, amount, normalizedChainId());
    }

    function mapERC721(
        IERC721Upgradeable token,
        uint256 tokenId,
        bytes32 recipient
    ) external payable nonReentrant whenNotPaused chargeFee(msg.value) {
        require(address(token) != address(0), "token");
        require(_tokenIdReserve[token][tokenId] == 0, "reserved");
        require(recipient != bytes32(0), "recipient");
        require(block.number > 0, "block number");

        TokenInfo memory info = _tokenInfos[address(token)];
        if (!info.initialized) {
            _initERC721(info, token, false);
        }
        require(info.tokenType == TokenType.ERC721, "type");
        require(!info.wrapped, "wrapped");

        require(token.ownerOf(tokenId) != address(this), "owner");
        token.safeTransferFrom(_msgSender(), address(this), tokenId);
        require(token.ownerOf(tokenId) == address(this), "transfer");

        _tokenIdReserve[token][tokenId] = block.number;
        info.reserve += 1;
        _tokenInfos[address(token)] = info;
        emit ERC721TokenMapped(
            address(token),
            _msgSender(),
            recipient,
            tokenId,
            normalizedChainId()
        );
    }

    function unmapERC20(
        IERC20Upgradeable token,
        bytes32 sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 share,
        bytes calldata signatures
    ) external payable nonReentrant whenNotPaused chargeFee(msg.value) {
        {
            bytes32 structHash = keccak256(
                abi.encode(
                    _UNMAP_ERC20_TYPEHASH,
                    token,
                    sender,
                    recipient,
                    txnHash,
                    txnHeight,
                    share
                )
            );
            require(verify(structHash, signatures), "verify");
        }
        require(sender != bytes32(0), "sender");
        require(recipient != address(0) && recipient != address(this), "recipient");
        // address(1) represents ETH on Raicoin network
        require(address(token) > address(1), "token");
        require(share > 0, "amount");
        require(block.number > 0, "block number");
        require(_unmappedTxns[txnHash] == 0, "mapped");
        _unmappedTxns[txnHash] = block.number;

        TokenInfo memory info = _tokenInfos[address(token)];
        require(info.initialized, "init");
        require(info.tokenType == TokenType.ERC20, "type");
        require(!info.wrapped, "wrapped");

        uint256 amount = share;
        uint256 balance = token.balanceOf(address(this));
        if (info.versatile || balance < info.reserve) {
            amount = (share * balance) / info.reserve;
        }
        require(amount > 0, "amount");
        info.reserve -= share;
        _tokenInfos[address(token)] = info;
        SafeERC20Upgradeable.safeTransferFrom(token, address(this), recipient, amount);
        emit ERC20TokenUnmapped(
            address(token),
            sender,
            recipient,
            txnHash,
            txnHeight,
            amount,
            share,
            normalizedChainId()
        );
    }

    function unmapETH(
        bytes32 sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 amount,
        bytes calldata signatures
    ) external payable nonReentrant whenNotPaused chargeFee(msg.value) {
        {
            bytes32 structHash = keccak256(
                abi.encode(_UNMAP_ETH_TYPEHASH, sender, recipient, txnHash, txnHeight, amount)
            );
            require(verify(structHash, signatures), "verify");
        }
        require(sender != bytes32(0), "sender");
        require(recipient != address(0) && recipient != address(this), "recipient");
        require(amount > 0, "amount");
        require(block.number > 0, "block number");
        require(_unmappedTxns[txnHash] == 0, "mapped");
        _unmappedTxns[txnHash] = block.number;

        _ethReserve -= amount;
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "call");

        emit ETHUnmapped(sender, recipient, txnHash, txnHeight, amount, normalizedChainId());
    }

    function unmapERC721(
        IERC721Upgradeable token,
        bytes32 sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 tokenId,
        bytes calldata signatures
    ) external payable nonReentrant whenNotPaused chargeFee(msg.value) {
        {
            bytes32 structHash = keccak256(
                abi.encode(
                    _UNMAP_ERC721_TYPEHASH,
                    token,
                    sender,
                    recipient,
                    txnHash,
                    txnHeight,
                    tokenId
                )
            );
            require(verify(structHash, signatures), "verify");
        }
        require(sender != bytes32(0), "sender");
        require(recipient != address(0) && recipient != address(this), "recipient");
        require(address(token) > address(1), "token");
        require(_tokenIdReserve[token][tokenId] != 0, "tokenId");
        require(_unmappedTxns[txnHash] == 0, "mapped");
        require(block.number > 0, "block number");
        _unmappedTxns[txnHash] = block.number;

        TokenInfo memory info = _tokenInfos[address(token)];
        require(info.initialized, "init");
        require(info.tokenType == TokenType.ERC721, "type");
        require(!info.wrapped, "wrapped");
        require(token.ownerOf(tokenId) == address(this), "owner");

        _tokenIdReserve[token][tokenId] = 0;
        info.reserve -= 1;
        _tokenInfos[address(token)] = info;
        token.safeTransferFrom(address(this), recipient, tokenId);
        require(token.ownerOf(tokenId) != address(this), "transfer");

        emit ERC721TokenUnmapped(
            address(token),
            sender,
            recipient,
            txnHash,
            txnHeight,
            tokenId,
            normalizedChainId()
        );
    }

    function createWrappedERC20Token(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract,
        uint8 decimals,
        bytes calldata signatures
    ) external {
        {
            bytes32 structHash = keccak256(
                abi.encode(
                    _CREATE_WRAPPED_ERC20_TOKEN_TYPEHASH,
                    keccak256(bytes(name)),
                    keccak256(bytes(symbol)),
                    keccak256(bytes(originalChain)),
                    originalChainId,
                    originalContract,
                    decimals
                )
            );
            require(verify(structHash, signatures), "verify");
        }
        require(_wrappedTokens[originalChainId][originalContract] == address(0), "created");

        address addr = _rai20Factory.create(
            name,
            symbol,
            originalChain,
            originalChainId,
            originalContract,
            decimals
        );
        require(addr != address(0), "create");

        {
            _wrappedTokens[originalChainId][originalContract] = addr;
            TokenInfo memory info;
            _initERC20(info, IERC20Upgradeable(addr), true);
        }

        emit WrappedERC20TokenCreated(
            originalChainId,
            originalContract,
            addr,
            name,
            symbol,
            originalChain,
            decimals,
            normalizedChainId()
        );
    }

    function createWrappedERC721Token(
        string calldata name,
        string calldata symbol,
        string calldata originalChain,
        uint32 originalChainId,
        bytes32 originalContract,
        bytes calldata signatures
    ) external {
        {
            bytes32 structHash = keccak256(
                abi.encode(
                    _CREATE_WRAPPED_ERC721_TOKEN_TYPEHASH,
                    keccak256(bytes(name)),
                    keccak256(bytes(symbol)),
                    keccak256(bytes(originalChain)),
                    originalChainId,
                    originalContract
                )
            );
            require(verify(structHash, signatures), "verify");
        }
        require(_wrappedTokens[originalChainId][originalContract] == address(0), "created");

        address addr = _rai721Factory.create(
            name,
            symbol,
            originalChain,
            originalChainId,
            originalContract
        );
        require(addr != address(0), "create");

        {
            _wrappedTokens[originalChainId][originalContract] = addr;
            TokenInfo memory info;
            _initERC721(info, IERC721Upgradeable(addr), true);
        }

        emit WrappedERC721TokenCreated(
            originalChainId,
            originalContract,
            addr,
            name,
            symbol,
            originalChain,
            normalizedChainId()
        );
    }

    function wrapERC20Token(
        uint32 originalChainId,
        bytes32 originalContract,
        bytes32 sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 amount,
        bytes calldata signatures
    ) external payable chargeFee(msg.value) {
        {
            bytes32 structHash = keccak256(
                abi.encode(
                    _WRAP_ERC20_TOKEN_TYPEHASH,
                    originalChainId,
                    originalContract,
                    sender,
                    recipient,
                    txnHash,
                    txnHeight,
                    amount
                )
            );
            require(verify(structHash, signatures), "verify");
        }
        require(originalChainId != normalizedChainId(), "chainId");
        require(sender != bytes32(0), "sender");
        require(recipient != address(0) && recipient != address(this), "recipient");
        require(amount > 0, "amount");

        address addr = _wrappedTokens[originalChainId][originalContract];
        require(addr != address(0), "missing");
        {
            TokenInfo memory info = _tokenInfos[addr];
            require(info.initialized, "init");
            require(info.tokenType == TokenType.ERC20, "type");
            require(info.wrapped, "not wrap");
        }
        IRAI20(addr).mint(recipient, amount);
        emit ERC20TokenWrapped(
            originalChainId,
            originalContract,
            sender,
            recipient,
            txnHash,
            txnHeight,
            addr,
            amount,
            normalizedChainId()
        );
    }

    function wrapERC721Token(
        uint32 originalChainId,
        bytes32 originalContract,
        bytes32 sender,
        address recipient,
        bytes32 txnHash,
        uint64 txnHeight,
        uint256 tokenId,
        bytes calldata signatures
    ) external payable chargeFee(msg.value) {
        {
            bytes32 structHash = keccak256(
                abi.encode(
                    _WRAP_ERC721_TOKEN_TYPEHASH,
                    originalChainId,
                    originalContract,
                    sender,
                    recipient,
                    txnHash,
                    txnHeight,
                    tokenId
                )
            );
            require(verify(structHash, signatures), "verify");
        }
        require(originalChainId != normalizedChainId(), "chainId");
        require(sender != bytes32(0), "sender");
        require(recipient != address(0) && recipient != address(this), "recipient");

        address addr = _wrappedTokens[originalChainId][originalContract];
        require(addr != address(0), "missing");
        {
            TokenInfo memory info = _tokenInfos[addr];
            require(info.initialized, "init");
            require(info.tokenType == TokenType.ERC721, "type");
            require(info.wrapped, "not wrap");
        }
        IRAI721(addr).mint(recipient, tokenId);
        emit ERC721TokenWrapped(
            originalChainId,
            originalContract,
            sender,
            recipient,
            txnHash,
            txnHeight,
            addr,
            tokenId,
            normalizedChainId()
        );
    }

    function unwrapERC20Token(
        IERC20Upgradeable token,
        uint256 amount,
        bytes32 recipient
    ) external payable chargeFee(msg.value) {
        require(recipient != bytes32(0), "recipient");
        require(amount > 0, "amount");

        {
            TokenInfo memory info = _tokenInfos[address(token)];
            require(info.initialized, "init");
            require(info.tokenType == TokenType.ERC20, "type");
            require(info.wrapped, "not wrap");
        }

        SafeERC20Upgradeable.safeTransferFrom(token, _msgSender(), address(this), amount);
        IRAI20(address(token)).burn(amount);

        emit ERC20TokenUnwrapped(
            IRAI20(address(token)).originalChainId(),
            IRAI20(address(token)).originalContract(),
            address(this),
            recipient,
            address(token),
            amount,
            normalizedChainId()
        );
    }

    function unwrapERC721Token(
        IERC721Upgradeable token,
        uint256 tokenId,
        bytes32 recipient
    ) external payable chargeFee(msg.value) {
        require(recipient != bytes32(0), "recipient");

        {
            TokenInfo memory info = _tokenInfos[address(token)];
            require(info.initialized, "init");
            require(info.tokenType == TokenType.ERC721, "type");
            require(info.wrapped, "not wrap");
        }

        token.safeTransferFrom(_msgSender(), address(this), tokenId);
        IRAI721(address(token)).burn(tokenId);

        emit ERC721TokenUnwrapped(
            IRAI721(address(token)).originalChainId(),
            IRAI721(address(token)).originalContract(),
            address(this),
            recipient,
            address(token),
            tokenId,
            normalizedChainId()
        );
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function newImplementation() external view returns (address) {
        return _newImplementation;
    }

    function normalizedChainId() public view virtual returns (uint32);

    function _authorizeUpgrade(address impl) internal virtual override {
        require(impl != address(0) && impl == _newImplementation, "impl");
        _newImplementation = address(0);
    }

    function _initERC20(
        TokenInfo memory info,
        IERC20Upgradeable token,
        bool wrapped
    ) private {
        require(!info.initialized, "initialized");
        info.decimals = IDecimals(address(token)).decimals();
        info.tokenType = TokenType.ERC20;
        info.wrapped = wrapped;
        info.initialized = true;
        _tokenInfos[address(token)] = info;
        emit TokenInfoInitialized(
            address(token),
            info.tokenType,
            info.wrapped,
            info.decimals,
            normalizedChainId()
        );
    }

    function _initERC721(
        TokenInfo memory info,
        IERC721Upgradeable token,
        bool wrapped
    ) private {
        require(!info.initialized, "initialized");
        require(
            ERC165CheckerUpgradeable.supportsInterface(
                address(token),
                type(IERC721Upgradeable).interfaceId
            ),
            "interfaceId"
        );
        info.decimals = 0;
        info.tokenType = TokenType.ERC721;
        info.wrapped = wrapped;
        info.initialized = true;
        _tokenInfos[address(token)] = info;
        emit TokenInfoInitialized(
            address(token),
            info.tokenType,
            info.wrapped,
            info.decimals,
            normalizedChainId()
        );
    }
}
