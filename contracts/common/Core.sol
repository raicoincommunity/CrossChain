// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

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
import "./errors.sol";

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
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*=========================== 1. STRUCTS =================================*/
    enum TokenType {
        INVALID,
        ERC20,
        ERC721
    }

    struct TokenInfo {
        uint256 reserve;
        TokenType tokenType;
        bool volatile; // the balance is subject to external changes, e.g. SafeMoon
        bool wrapped;
        bool initialized;
        uint8 decimals;
    }

    /*=========================== 2. CONSTANTS ===============================*/
    bytes32 private constant _UPGRADE_TYPEHASH =
        keccak256("Upgrade(address newImplementation,uint256 nonce)");
    bytes32 private constant _UNMAP_ERC20_TYPEHASH =
        keccak256(
            "UnmapERC20(address token,bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 share)"
        );
    bytes32 private constant _UNMAP_ETH_TYPEHASH =
        keccak256(
            "UnmapETH(bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 amount)"
        );
    bytes32 private constant _UNMAP_ERC721_TYPEHASH =
        keccak256(
            "UnmapERC721(address token,bytes32 sender,address recipient,bytes32 txnHash,uint64 txnHeight,uint256 tokenId)"
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
    // mapping submitted transaction hash to block height at which the submission was executed
    // it is used to prevent double-spending of unmap transactions
    mapping(bytes32 => uint256) private _submittedTxns;
    // maping original (chain, token address) to wrapped token address
    mapping(uint32 => mapping(bytes32 => address)) private _wrappedTokens;

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
        if (!verify(structHash, signatures)) revert VerificationFailed();
        if (impl == address(0) || impl == _getImplementation()) revert InvalidImplementation();

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
        if (address(token) <= address(1)) revert InvalidTokenAddress();
        if (amount <= 1) revert InvalidAmount();
        if (recipient == bytes32(0)) revert InvalidRecipient();

        TokenInfo memory info = _tokenInfos[address(token)];
        if (!info.initialized) {
            _initERC20(info, token, false);
        }
        if (info.tokenType != TokenType.ERC20) revert TokenTypeNotMatch();
        if (info.wrapped) revert CanNotMapWrappedToken();

        uint256 balance = token.balanceOf(address(this));
        token.safeTransferFrom(_msgSender(), address(this), amount);
        uint256 newBalance = token.balanceOf(address(this));
        if (newBalance <= balance + 1) revert InvalidBalance();

        if (info.reserve == 0 && balance > 0) {
            info.reserve = balance;
        }
        uint256 share = newBalance - balance;
        if ((balance > 0 && info.reserve > 0) && (balance < info.reserve || info.volatile)) {
            share = (share * info.reserve) / balance;
        }
        if (share == 0) revert InvalidShare();

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
        if (amount == 0) revert InvalidAmount();
        if (recipient == bytes32(0)) revert InvalidRecipient();
        if (msg.value != (amount + fee)) revert InvalidValue();

        _ethReserve += amount;
        emit ETHMapped(_msgSender(), recipient, amount, normalizedChainId());
    }

    function mapERC721(
        IERC721Upgradeable token,
        uint256 tokenId,
        bytes32 recipient
    ) external payable nonReentrant whenNotPaused chargeFee(msg.value) {
        if (address(token) <= address(1)) revert InvalidTokenAddress();
        if (_tokenIdReserve[token][tokenId] != 0) revert TokenIdAlreadyMapped();
        if (recipient == bytes32(0)) revert InvalidRecipient();
        if (block.number == 0) revert ZeroBlockNumber();

        TokenInfo memory info = _tokenInfos[address(token)];
        if (!info.initialized) {
            _initERC721(info, token, false);
        }
        if (info.tokenType != TokenType.ERC721) revert TokenTypeNotMatch();
        if (info.wrapped) revert CanNotMapWrappedToken();

        if (token.ownerOf(tokenId) == address(this)) revert TokenIdAlreadyOwned();
        token.safeTransferFrom(_msgSender(), address(this), tokenId);
        if (token.ownerOf(tokenId) != address(this)) revert TransferFailed();

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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (sender == bytes32(0)) revert InvalidSender();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        // address(1) represents ETH on Raicoin network
        if (address(token) <= address(1)) revert InvalidTokenAddress();
        if (share == 0) revert InvalidShare();
        if (_submittedTxns[txnHash] != 0) revert AlreadySubmitted();
        if (block.number == 0) revert ZeroBlockNumber();
        _submittedTxns[txnHash] = block.number;

        TokenInfo memory info = _tokenInfos[address(token)];
        if (!info.initialized) revert TokenNotInitialized();
        if (info.tokenType != TokenType.ERC20) revert TokenTypeNotMatch();
        if (info.wrapped) revert CanNotUnmapWrappedToken();

        uint256 amount = share;
        uint256 balance = token.balanceOf(address(this));
        if (balance < info.reserve || info.volatile) {
            amount = (share * balance) / info.reserve;
        }
        if (amount == 0) revert InvalidAmount();

        info.reserve -= share;
        _tokenInfos[address(token)] = info;
        token.safeTransfer(recipient, amount);
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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (sender == bytes32(0)) revert InvalidSender();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (_submittedTxns[txnHash] != 0) revert AlreadySubmitted();
        if (block.number == 0) revert ZeroBlockNumber();
        _submittedTxns[txnHash] = block.number;

        _ethReserve -= amount;

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed();

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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (sender == bytes32(0)) revert InvalidSender();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        if (address(token) <= address(1)) revert InvalidTokenAddress();
        if (_tokenIdReserve[token][tokenId] == 0) revert TokenIdNotMapped();
        if (_submittedTxns[txnHash] != 0) revert AlreadySubmitted();
        if (block.number == 0) revert ZeroBlockNumber();
        _submittedTxns[txnHash] = block.number;

        TokenInfo memory info = _tokenInfos[address(token)];
        if (!info.initialized) revert TokenNotInitialized();
        if (info.tokenType != TokenType.ERC721) revert TokenTypeNotMatch();
        if (info.wrapped) revert CanNotUnmapWrappedToken();
        if (token.ownerOf(tokenId) != address(this)) revert TokenIdNotOwned();

        _tokenIdReserve[token][tokenId] = 0;
        info.reserve -= 1;
        _tokenInfos[address(token)] = info;
        token.safeTransferFrom(address(this), recipient, tokenId);
        if (token.ownerOf(tokenId) == address(this)) revert TransferFailed();

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
    ) external nonReentrant whenNotPaused {
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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (originalChainId == normalizedChainId() || originalChainId == 0) {
            revert InvalidOriginalChainId();
        }
        if (originalContract == bytes32(0)) revert InvalidOriginalContract();

        if (_wrappedTokens[originalChainId][originalContract] != address(0)) {
            revert WrappedTokenAlreadyCreated();
        }

        address addr = _rai20Factory.create(
            name,
            symbol,
            originalChain,
            originalChainId,
            originalContract,
            decimals
        );
        if (addr == address(0)) revert CreateWrappedTokenFailed();

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
    ) external nonReentrant whenNotPaused {
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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }

        if (originalChainId == normalizedChainId() || originalChainId == 0) {
            revert InvalidOriginalChainId();
        }
        if (originalContract == bytes32(0)) revert InvalidOriginalContract();

        if (_wrappedTokens[originalChainId][originalContract] != address(0)) {
            revert WrappedTokenAlreadyCreated();
        }

        address addr = _rai721Factory.create(
            name,
            symbol,
            originalChain,
            originalChainId,
            originalContract
        );
        if (addr == address(0)) revert CreateWrappedTokenFailed();

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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (originalChainId == normalizedChainId() || originalChainId == 0) {
            revert InvalidOriginalChainId();
        }
        if (originalContract == bytes32(0)) revert InvalidOriginalContract();
        if (sender == bytes32(0)) revert InvalidSender();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (_submittedTxns[txnHash] != 0) revert AlreadySubmitted();
        if (block.number == 0) revert ZeroBlockNumber();
        _submittedTxns[txnHash] = block.number;

        address addr = _wrappedTokens[originalChainId][originalContract];
        if (addr == address(0)) revert WrappedTokenNotCreated();

        {
            TokenInfo memory info = _tokenInfos[addr];
            if (!info.initialized) revert TokenNotInitialized();
            if (info.tokenType != TokenType.ERC20) revert TokenTypeNotMatch();
            if (!info.wrapped) revert NotWrappedToken();
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
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (originalChainId == normalizedChainId() || originalChainId == 0) {
            revert InvalidOriginalChainId();
        }
        if (originalContract == bytes32(0)) revert InvalidOriginalContract();

        if (sender == bytes32(0)) revert InvalidSender();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();

        if (_submittedTxns[txnHash] != 0) revert AlreadySubmitted();
        if (block.number == 0) revert ZeroBlockNumber();
        _submittedTxns[txnHash] = block.number;

        address addr = _wrappedTokens[originalChainId][originalContract];
        if (addr == address(0)) revert WrappedTokenNotCreated();

        {
            TokenInfo memory info = _tokenInfos[addr];
            if (!info.initialized) revert TokenNotInitialized();
            if (info.tokenType != TokenType.ERC721) revert TokenTypeNotMatch();
            if (!info.wrapped) revert NotWrappedToken();
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
        if (address(token) == address(0)) revert InvalidTokenAddress();
        if (recipient == bytes32(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();

        {
            TokenInfo memory info = _tokenInfos[address(token)];
            if (!info.initialized) revert TokenNotInitialized();
            if (info.tokenType != TokenType.ERC20) revert TokenTypeNotMatch();
            if (!info.wrapped) revert NotWrappedToken();
        }

        token.safeTransferFrom(_msgSender(), address(this), amount);
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
        if (address(token) == address(0)) revert InvalidTokenAddress();
        if (recipient == bytes32(0)) revert InvalidRecipient();

        {
            TokenInfo memory info = _tokenInfos[address(token)];
            if (!info.initialized) revert TokenNotInitialized();
            if (info.tokenType != TokenType.ERC721) revert TokenTypeNotMatch();
            if (!info.wrapped) revert NotWrappedToken();
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

    function wrappedToken(uint32 originalChainId, bytes32 originalContract)
        external
        view
        returns (address)
    {
        return _wrappedTokens[originalChainId][originalContract];
    }

    function tokenInfo(address token) external view returns (TokenInfo memory) {
        return _tokenInfos[token];
    }

    function normalizedChainId() public view virtual returns (uint32);

    function _authorizeUpgrade(address impl) internal virtual override {
        if (impl == address(0) || impl != _newImplementation) revert InvalidImplementation();
        _newImplementation = address(0);
    }

    function _initERC20(
        TokenInfo memory info,
        IERC20Upgradeable token,
        bool wrapped
    ) private {
        if (info.initialized) revert TokenAlreadyInitialized();
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
        if (info.initialized) revert TokenAlreadyInitialized();
        if (
            !ERC165CheckerUpgradeable.supportsInterface(
                address(token),
                type(IERC721Upgradeable).interfaceId
            )
        ) {
            revert NotERC721Token();
        }

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
