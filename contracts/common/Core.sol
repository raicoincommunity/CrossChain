// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./CustomEIP712Upgradeable.sol";

interface IDecimals {
    function decimals() external view returns (uint8);
}

abstract contract Core is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    CustomEIP712Upgradeable
{
    /*=========================== CONSTANTS ==================================*/
    uint256 private constant MIN_WEIGHT = 2e16;
    uint256 private constant CONFIRM_PERCENT = 51;
    uint256 private constant EPOCH_TIME = 72 * 3600; // 72 hours
    uint256 private constant REWARD_TIME = 71 * 3600; // reward: 0 ~ 71 hour, purge: 71 ~ 72 hour

    // solhint-disable var-name-mixedcase
    bytes32 private constant _PAUSE_TYPEHASH = keccak256("Pause(uint256 nonce)");
    bytes32 private constant _UNPAUSE_TYPEHASH = keccak256("Unpause(uint256 nonce)");
    bytes32 private constant _UPGRADE_TYPEHASH =
        keccak256("Upgrade(address newImplementation,uint256 nonce)");
    bytes32 private constant _SUBMIT_VALIDATOR_TYPEHASH =
        keccak256("SubmitValidator(bytes32 validator,address signer,uint256 weight,uint32 epoch)");
    bytes32 private constant _UPDATE_FEE_RATE_TYPEHASH =
        keccak256("UpdateFeeRate(uint256 feeRate,uint256 nonce)");

    /*=========================== TYPEDEF ====================================*/
    struct ValidatorInfo {
        uint256 weightedGasPrice;
        address signer;
        uint64 lastSubmit;
        uint32 epoch;
    }

    enum TokenType {
        INVALID,
        ERC20,
        ERC721
    }

    struct TokenInfo {
        uint256 reserve;
        TokenType tokenType;
        bool versatile; // inflation or deflation
        bool wrapped;
        bool initialized;
        uint8 decimals;
    }

    /*=========================== STATE VARIABLES ============================*/
    address public newImplementation;
    address public genesisSigner;
    bytes32 public genesisValidator;
    uint256 public totalWeight;
    uint256 public weightedGasPrice;
    uint256 public feeInPool;
    uint256 public nonce;
    uint256 public feeRate; // gas as unit
    uint256 public ethReserve;

    // Mapping from signer's address to election weight
    mapping(address => uint256) private _weights;
    // Mapping from signer's address to validator's address (public key)
    mapping(address => bytes32) private _signerToValidator;

    mapping(bytes32 => ValidatorInfo) private _validatorInfos;
    // Array with all token ids, used for enumeration
    bytes32[] private _validators;

    mapping(address => TokenInfo) private _tokenInfos;

    /*=========================== EVENTS =====================================*/
    event FeeRateUpdated(uint256 feeRate, uint256 nonce);

    event ValidatorSubmitted(
        bytes32 indexed validator,
        address indexed signer,
        uint256 weight,
        uint32 epoch
    );

    event ValidatorPurged(bytes32 indexed validator, uint32 epoch);

    event RewardSent(address indexed to, uint256 amount);
    event TokenInfoInitialized(
        address indexed token,
        TokenType tokenType,
        bool wrapped,
        uint8 decimals
    );

    event FeeCharged(address indexed sender, uint256 fee);

    event ERC20TokenMapped(
        address indexed token,
        address indexed sender,
        bytes32 indexed recipient,
        uint256 amount,
        uint256 share
    );

    event ETHMapped(address indexed sender, bytes32 indexed recipient, uint256 amount);

    /*=========================== MODIFIERS ==================================*/
    modifier useNonce(uint256 nonce_) {
        require(nonce == nonce_, "nonce");
        nonce++;
        _;
    }

    modifier verified(bytes32 typedHash, bytes calldata signatures) {
        require(verify(typedHash, signatures), "verify");
        _;
    }

    modifier onlySigner(address signer) {
        require(msg.sender == signer && tx.origin == signer, "Not from signer");
        _;
    }

    modifier chargeFee(uint256 fee) {
        uint256 minFee = feeRate * weightedGasPrice;
        require(msg.value >= fee && fee >= minFee, "fee");
        if (fee > 0) {
            feeInPool += fee;
            emit FeeCharged(_msgSender(), fee);
        }
        _;
    }

    /*=========================== FUNCTIONS ==================================*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __Core_init() internal onlyInitializing {
        // todo: unchain_init
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __EIP712_init();
        __Core_init_unchained();
    }

    function __Core_init_unchained() internal onlyInitializing {
        feeRate = 21000;
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function pause(
        uint256 nonce_,
        bytes32 typedHash,
        bytes calldata signatures
    ) external whenNotPaused useNonce(nonce_) verified(typedHash, signatures) {
        require(typedHash == keccak256(abi.encode(_PAUSE_TYPEHASH, nonce_)), "hash");

        _pause();
    }

    function unpause(
        uint256 nonce_,
        bytes32 typedHash,
        bytes calldata signatures
    ) external whenPaused useNonce(nonce_) verified(typedHash, signatures) {
        require(typedHash == keccak256(abi.encode(_UNPAUSE_TYPEHASH, nonce_)), "hash");
        _unpause();
    }

    function upgrade(
        address impl,
        uint256 nonce_,
        bytes32 typedHash,
        bytes calldata signatures
    ) external whenNotPaused useNonce(nonce_) verified(typedHash, signatures) {
        require(typedHash == keccak256(abi.encode(_UPGRADE_TYPEHASH, impl, nonce_)), "hash");
        require(impl != _getImplementation(), "impl");
        newImplementation = impl;
    }

    function updateFeeRate(
        uint256 feeRate_,
        uint256 nonce_,
        bytes32 typedHash,
        bytes calldata signatures
    ) external whenNotPaused useNonce(nonce_) verified(typedHash, signatures) {
        require(
            typedHash == keccak256(abi.encode(_UPDATE_FEE_RATE_TYPEHASH, feeRate_, nonce_)),
            "hash"
        );
        feeRate = feeRate_;
        emit FeeRateUpdated(feeRate_, nonce_);
    }

    function submitValidator(
        bytes32 validator,
        address signer,
        uint256 weight,
        uint32 epoch,
        address rewardTo,
        bytes32 typedHash,
        bytes calldata signatures
    ) external whenNotPaused nonReentrant verified(typedHash, signatures) onlySigner(signer) {
        {
            // Statck too deep
            bytes32 actualHash = keccak256(
                abi.encode(_SUBMIT_VALIDATOR_TYPEHASH, validator, signer, weight, epoch)
            );
            require(typedHash == actualHash, "hash");
        }
        require(validator != bytes32(0) && validator != genesisValidator, "validator");
        require(signer != address(0) && signer != genesisSigner, "signer");

        ValidatorInfo memory info = _validatorInfos[validator];
        require(epoch >= info.epoch && epoch == _getCurrentEpoch(), "epoch");

        uint256 reward = _revokeSubmission(validator, info, false);
        if (!_inRewardTimeRange(info) || info.epoch == epoch) {
            reward = 0;
        }

        require(_signerToValidator[signer] == bytes32(0), "signer");
        require(_weights[signer] == 0, "weight");

        if (info.epoch == 0) {
            _validators.push(validator);
        }

        info.signer = signer;
        info.lastSubmit = uint64(block.timestamp);
        info.epoch = epoch;
        _doSubmission(validator, info, weight);
        emit ValidatorSubmitted(validator, signer, weight, epoch);

        if (reward > 0 && rewardTo != address(0)) {
            _sendReward(rewardTo, reward);
        }
    }

    function purgeValidators(bytes32[] calldata validators, address rewardTo)
        external
        whenNotPaused
        nonReentrant
    {
        require(_inPurgeTimeRange(), "time");
        uint256 reward = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            bytes32 validator = validators[i];
            ValidatorInfo memory info = _validatorInfos[validator];
            if (_canPurge(info)) {
                reward += _revokeSubmission(validator, info, true);
                emit ValidatorPurged(validator, info.epoch);
            }
        }

        if (reward > 0 && rewardTo != address(0)) {
            _sendReward(rewardTo, reward);
        }
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
    ) external payable whenNotPaused nonReentrant chargeFee(msg.value) {
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
        emit ERC20TokenMapped(address(token), _msgSender(), recipient, amount, share);
    }

    function mapETH(
        uint256 amount,
        bytes32 recipient,
        uint256 fee
    ) external payable whenNotPaused nonReentrant chargeFee(fee) {
        require(amount > 0, "amount");
        require(recipient != bytes32(0), "recipient");
        require(msg.value == amount + fee, "value");

        ethReserve += amount;
        emit ETHMapped(_msgSender(), recipient, amount);
    }

    function getWeight(address signer) external view returns (uint256) {
        return _getWeight(signer, genesisSigner, totalWeight);
    }

    function verify(bytes32 msgHash, bytes calldata signatures) public view returns (bool) {
        uint256 length = signatures.length;
        require(length > 0 && length % 65 == 0, "signatures");
        uint256 count = length / 65;

        uint256 total = totalWeight;
        address genesis = genesisSigner;
        address last = address(0);
        address current;

        bytes32 r;
        bytes32 s;
        uint8 v;
        uint256 i;

        uint256 weight = 0;

        for (i = 0; i < count; ++i) {
            (r, s, v) = _decodeSignature(signatures, i);
            current = ecrecover(msgHash, v, r, s);
            require(current > last, "signer");
            last = current;
            weight += _getWeight(current, genesis, total);
        }

        uint256 adjustTotal = total > MIN_WEIGHT ? total : MIN_WEIGHT;
        return weight > (adjustTotal * CONFIRM_PERCENT) / 100;
    }

    function _decodeSignature(bytes calldata signatures, uint256 index)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        // |{bytes32 r}{bytes32 s}{uint8 v}|...|{bytes32 r}{bytes32 s}{uint8 v}|
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let start := signatures.offset
            let offset := mul(0x41, index)
            r := calldataload(add(start, offset))
            s := calldataload(add(start, add(offset, 0x20)))
            v := and(calldataload(add(start, add(offset, 0x21))), 0xff)
        }
    }

    function _getWeight(
        address signer,
        address genesis,
        uint256 total
    ) internal view returns (uint256) {
        if (signer != genesis) {
            return _weights[signer];
        } else {
            return total >= MIN_WEIGHT ? 0 : MIN_WEIGHT - total;
        }
    }

    function _authorizeUpgrade(address impl) internal override {
        require(impl != address(0) && impl == newImplementation, "impl");
        newImplementation = address(0);
    }

    function _getCurrentEpoch() internal view returns (uint32) {
        return uint32(block.timestamp / EPOCH_TIME);
    }

    function _doSubmission(
        bytes32 validator,
        ValidatorInfo memory info,
        uint256 weight
    ) private {
        address signer = info.signer;
        _signerToValidator[signer] = validator;
        _weights[signer] = weight;
        totalWeight += weight;

        info.weightedGasPrice = _getWeightedGasPrice(weight);
        weightedGasPrice += info.weightedGasPrice;
        _validatorInfos[validator] = info;
    }

    function _revokeSubmission(
        bytes32 validator,
        ValidatorInfo memory info,
        bool store
    ) private returns (uint256 reward) {
        bool changed = false;
        address signer = info.signer;
        if (signer != address(0)) {
            info.signer = address(0);
            changed = true;
            _signerToValidator[signer] = bytes32(0);
            uint256 weight = _weights[signer];
            if (weight > 0) {
                _weights[signer] = 0;
                uint256 total = totalWeight;
                reward = (weight * feeInPool) / total;
                totalWeight = total - weight;
            }
        }

        if (info.weightedGasPrice > 0) {
            weightedGasPrice -= info.weightedGasPrice;
            info.weightedGasPrice = 0;
            changed = true;
        }

        if (store && changed) {
            _validatorInfos[validator] = info;
        }
    }

    function _getWeightedGasPrice(uint256 weight) internal view returns (uint256) {
        if (weight == 0) {
            return 0;
        }
        uint256 total = totalWeight;
        require(total > 0, "totalWeight");
        return (weight * tx.gasprice) / total;
    }

    function _sendReward(address to, uint256 amount) internal {
        uint256 fee = feeInPool;
        if (amount > fee) {
            amount = fee;
        }
        if (amount == 0) {
            return;
        }
        feeInPool = fee - amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "reward");

        emit RewardSent(to, amount);
    }

    function _inRewardTimeRange(ValidatorInfo memory info) internal view returns (bool) {
        uint256 rewardTime = REWARD_TIME;
        uint256 epochTime = EPOCH_TIME;
        uint256 hour = 3600;
        uint256 lastDelay = info.lastSubmit % epochTime;
        if (lastDelay > rewardTime) {
            lastDelay = rewardTime;
        }
        uint256 delay = (lastDelay + rewardTime - hour) % rewardTime;
        if (delay > rewardTime - hour) {
            delay = rewardTime - hour;
        }
        return (block.timestamp % epochTime) >= delay;
    }

    function _inPurgeTimeRange() internal view returns (bool) {
        return (block.timestamp % EPOCH_TIME) > REWARD_TIME;
    }

    function _canPurge(ValidatorInfo memory info) internal view returns (bool) {
        if (info.epoch >= _getCurrentEpoch()) {
            return false;
        }
        return info.weightedGasPrice != 0 || info.signer != address(0);
    }

    function _initERC20(
        TokenInfo memory info,
        IERC20Upgradeable token,
        bool wrapped
    ) internal {
        require(!info.initialized, "initialized");
        info.tokenType = TokenType.ERC20;
        info.wrapped = wrapped;
        info.decimals = IDecimals(address(token)).decimals();
        info.initialized = true;
        _tokenInfos[address(token)] = info;
        emit TokenInfoInitialized(address(token), info.tokenType, info.wrapped, info.decimals);
    }

    function normalizedChainId() public view virtual returns (uint32);

    function initialize() public virtual;
}
