// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./CustomEIP712Upgradeable.sol";
import "./NonceManager.sol";

contract ValidatorManager is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    CustomEIP712Upgradeable,
    NonceManager
{
    /*=========================== 1. STRUCTS =================================*/
    struct ValidatorInfo {
        uint256 gasPrice;
        address signer;
        uint64 lastSubmit;
        uint32 epoch;
    }

    /*=========================== 2. CONSTANTS ===============================*/
    uint256 private constant _MIN_WEIGHT = 2e16;
    uint256 private constant _CONFIRM_PERCENT = 51;
    uint256 private constant _EPOCH_TIME = 72 * 3600; // 72 hours
    uint256 private constant _REWARD_TIME = 71 * 3600; // reward: 0 ~ 71 hour, purge: 71 ~ 72 hour
    bytes32 private constant _SUBMIT_VALIDATOR_TYPEHASH =
        keccak256("SubmitValidator(bytes32 validator,address signer,uint256 weight,uint32 epoch)");
    bytes32 private constant _SET_FEE_RATE_TYPEHASH =
        keccak256("SetFeeRate(uint256 feeRate,uint256 nonce)");

    /*=========================== 3. STATE VARIABLES =========================*/
    address private _genesisSigner;
    bytes32 private _genesisValidator;
    uint256 private _totalWeight;
    uint256 private _weightedGasPrice;
    uint256 private _feeInPool;
    uint256 private _feeRate; // gas as unit

    // Mapping from signer's address to election _weightedGasPrice
    mapping(address => uint256) private _weights;

    // Mapping from signer's address to validator's address (public key)
    mapping(address => bytes32) private _signerToValidator;

    mapping(bytes32 => ValidatorInfo) private _validatorInfos;

    // Array with all token ids, used for enumeration
    bytes32[] private _validators;

    /*=========================== 4. EVENTS ==================================*/
    event FeeRateUpdated(uint256 feeRate, uint256 nonce);
    event ValidatorSubmitted(
        bytes32 indexed validator,
        address indexed signer,
        uint256 weight,
        uint32 epoch
    );
    event ValidatorPurged(
        bytes32 indexed validator,
        address indexed signer,
        uint256 weight,
        uint32 epoch
    );
    event RewardSent(address indexed to, uint256 amount);
    event FeeCharged(address indexed sender, uint256 fee);
    event WeightedGasPriceUpdated(uint256 previousPrice, uint256 newPrice);
    event TotalWeightUpdated(uint256 previousWeight, uint256 newWeight);

    /*=========================== 5. MODIFIERS ===============================*/
    modifier onlySigner(address signer) {
        require(msg.sender == signer && tx.origin == signer, "Not from signer");
        _;
    }

    modifier chargeFee(uint256 fee) {
        uint256 minFee = _feeRate * _weightedGasPrice;
        require(msg.value >= fee && fee >= minFee, "fee");
        if (fee > 0) {
            _feeInPool += fee;
            emit FeeCharged(msg.sender, fee);
        }
        _;
    }

    /*=========================== 6. FUNCTIONS ===============================*/
    function __ValidatorManager_init(bytes32 genesisValidator, address genesisSigner)
        internal
        onlyInitializing
    {
        __ValidatorManager_init_unchained(genesisValidator, genesisSigner);
    }

    function __ValidatorManager_init_unchained(bytes32 genesisValidator, address genesisSigner)
        internal
        onlyInitializing
    {
        _feeRate = 21000;
        _genesisSigner = genesisSigner;
        _genesisValidator = genesisValidator;
        _validators.push(genesisValidator);
    }

    function setFeeRate(
        uint256 feeRate,
        uint256 nonce,
        bytes calldata signatures
    ) external nonReentrant whenNotPaused useNonce(nonce) {
        require(
            verify(keccak256(abi.encode(_SET_FEE_RATE_TYPEHASH, feeRate, nonce)), signatures),
            "verify"
        );
        _feeRate = feeRate;
        emit FeeRateUpdated(feeRate, nonce);
    }

    function submitValidator(
        bytes32 validator,
        address signer,
        uint256 weight,
        uint32 epoch,
        address rewardTo,
        bytes calldata signatures
    ) external nonReentrant whenNotPaused onlySigner(signer) {
        {
            // Statck too deep
            bytes32 structHash = keccak256(
                abi.encode(_SUBMIT_VALIDATOR_TYPEHASH, validator, signer, weight, epoch)
            );
            require(verify(structHash, signatures), "verify");
        }
        require(validator != bytes32(0) && validator != _genesisValidator, "validator");
        require(signer != address(0) && signer != _genesisSigner, "signer");

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

        info.gasPrice = tx.gasprice;
        info.signer = signer;
        info.lastSubmit = uint64(block.timestamp);
        info.epoch = epoch;
        _doSubmission(validator, info, weight);

        if (reward > 0 && rewardTo != address(0)) {
            _sendReward(rewardTo, reward);
        }
    }

    function purgeValidators(bytes32[] calldata validators, address rewardTo)
        external
        nonReentrant
        whenNotPaused
    {
        require(_inPurgeTimeRange(), "time");
        uint256 reward = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            bytes32 validator = validators[i];
            ValidatorInfo memory info = _validatorInfos[validator];
            if (_canPurge(info)) {
                reward += _revokeSubmission(validator, info, true);
            }
        }

        if (reward > 0 && rewardTo != address(0)) {
            _sendReward(rewardTo, reward);
        }
    }

    function getWeight(address signer) external view returns (uint256) {
        return _getWeight(signer, _genesisSigner, _totalWeight);
    }

    function getFeeRate() external view returns (uint256) {
        return _feeRate;
    }

    function getFeeInPool() external view returns (uint256) {
        return _feeInPool;
    }

    function getWeightedGasPrice() external view returns (uint256) {
        return _weightedGasPrice;
    }

    function getTotalWeight() external view returns (uint256) {
        return _totalWeight;
    }

    function getValidatorInfo(bytes32 validator) external view returns (ValidatorInfo memory) {
        return _validatorInfos[validator];
    }

    function getValidators() external view returns (bytes32[] memory) {
        return _validators;
    }

    function getValidatorCount() external view returns (uint256) {
        return _validators.length;
    }

    function verify(bytes32 structHash, bytes calldata signatures) public view returns (bool) {
        bytes32 typedHash = _hashTypedDataV4(structHash);
        return _verify(typedHash, signatures);
    }

    function _verify(bytes32 msgHash, bytes calldata signatures) internal view returns (bool) {
        uint256 length = signatures.length;
        require(length > 0 && length % 65 == 0, "signatures");
        uint256 count = length / 65;

        uint256 total = _totalWeight;
        address genesis = _genesisSigner;
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
            require(current > last, "signer order");
            last = current;
            weight += _getWeight(current, genesis, total);
        }

        uint256 adjustTotal = total > _MIN_WEIGHT ? total : _MIN_WEIGHT;
        return weight > (adjustTotal * _CONFIRM_PERCENT) / 100;
    }

    function _getWeight(
        address signer,
        address genesis,
        uint256 total
    ) internal view returns (uint256) {
        if (signer != genesis) {
            return _weights[signer];
        } else {
            return total >= _MIN_WEIGHT ? 0 : _MIN_WEIGHT - total;
        }
    }

    function _getCurrentEpoch() internal view returns (uint32) {
        return uint32(block.timestamp / _EPOCH_TIME);
    }

    function _inRewardTimeRange(ValidatorInfo memory info) internal view returns (bool) {
        uint256 rewardTime = _REWARD_TIME;
        uint256 epochTime = _EPOCH_TIME;
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
        return (block.timestamp % _EPOCH_TIME) > _REWARD_TIME;
    }

    function _canPurge(ValidatorInfo memory info) internal view returns (bool) {
        if (info.epoch >= _getCurrentEpoch()) {
            return false;
        }
        return info.signer != address(0);
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

    function _doSubmission(
        bytes32 validator,
        ValidatorInfo memory info,
        uint256 weight
    ) private {
        address signer = info.signer;
        _signerToValidator[signer] = validator;
        _weights[signer] = weight;

        _validatorInfos[validator] = info;
        emit ValidatorSubmitted(validator, info.signer, weight, info.epoch);

        _increaseTotalWeightAndUpdateGasPrice(weight, info.gasPrice);
    }

    function _revokeSubmission(
        bytes32 validator,
        ValidatorInfo memory info,
        bool store
    ) private returns (uint256 reward) {
        address signer = info.signer;
        if (signer == address(0)) {
            return 0;
        }
        _signerToValidator[signer] = bytes32(0);
        uint256 weight = _weights[signer];
        _weights[signer] = 0;
        if (weight > 0) {
            uint256 total = _totalWeight;
            if (total > 0) {
                reward = (weight * _feeInPool) / total;
            }
        }
        _decreaseTotalWeightAndUpdateGasPrice(weight, info.gasPrice);

        info.gasPrice = 0;
        info.signer = address(0);
        if (store) {
            _validatorInfos[validator] = info;
            emit ValidatorPurged(validator, signer, weight, info.epoch);
        }
    }

    function _sendReward(address to, uint256 amount) private {
        uint256 fee = _feeInPool;
        if (amount > fee) {
            amount = fee;
        }
        if (amount == 0) {
            return;
        }
        _feeInPool = fee - amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "reward");

        emit RewardSent(to, amount);
    }

    function _increaseTotalWeightAndUpdateGasPrice(uint256 weight, uint256 gasPrice) private {
        if (weight == 0) {
            return;
        }

        uint256 currentWeight = _totalWeight;
        uint256 newWeight = currentWeight + weight;
        _totalWeight = newWeight;
        emit TotalWeightUpdated(currentWeight, newWeight);

        uint256 currentPrice = _weightedGasPrice;
        uint256 newPrice = ((currentPrice * currentWeight) + (weight * gasPrice)) / newWeight;
        _weightedGasPrice = newPrice;
        emit WeightedGasPriceUpdated(currentPrice, newPrice);
    }

    function _decreaseTotalWeightAndUpdateGasPrice(uint256 weight, uint256 gasPrice) private {
        if (weight == 0) {
            return;
        }

        uint256 currentWeight = _totalWeight;
        uint256 currentPrice = _weightedGasPrice;

        if (weight >= currentWeight) {
            _totalWeight = 0;
            emit TotalWeightUpdated(currentWeight, 0);
            _weightedGasPrice = 0;
            emit WeightedGasPriceUpdated(currentPrice, 0);
            return;
        }

        uint256 newWeight = currentWeight - weight;
        _totalWeight = newWeight;
        emit TotalWeightUpdated(currentWeight, newWeight);

        uint256 removalPrice = (gasPrice * weight) / currentWeight;
        if (removalPrice >= currentPrice) {
            _weightedGasPrice = 0;
            emit WeightedGasPriceUpdated(currentPrice, 0);
            return;
        }

        uint256 newPrice = ((currentPrice - removalPrice) * currentWeight) / newWeight;
        _weightedGasPrice = newPrice;
        emit WeightedGasPriceUpdated(currentPrice, newPrice);
    }
}
