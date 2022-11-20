// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./CustomEIP712.sol";
import "./NonceManager.sol";
import "./Component.sol";
import "./IVerifier.sol";
import "./errors.sol";

contract ValidatorManager is ReentrancyGuard, Pausable, CustomEIP712, NonceManager, Component {
    /*=========================== 1. STRUCTS =================================*/
    struct ValidatorInfo {
        uint256 gasPrice;
        address signer;
        uint64 lastSubmit;
        uint32 epoch;
    }

    struct ValidatorFullInfo {
        bytes32 validator;
        uint256 gasPrice;
        address signer;
        uint64 lastSubmit;
        uint32 epoch;
        uint256 weight;
    }

    /*=========================== 2. CONSTANTS ===============================*/
    uint256 private constant _MIN_WEIGHT = 2e16;
    uint256 private constant _CONFIRM_PERCENT = 51;
    uint256 private constant _EPOCH_TIME = 72 * 3600; // 72 hours
    uint256 private constant _REWARD_TIME = 71 * 3600; // reward: 0 ~ 71 hour, purge: 71 ~ 72 hour
    uint256 private constant _REWARD_FACTOR = 1e9;
    bytes32 private constant _SUBMIT_VALIDATOR_TYPEHASH =
        keccak256("SubmitValidator(bytes32 validator,address signer,uint256 weight,uint32 epoch)");
    bytes32 private constant _SET_FEE_RATE_TYPEHASH =
        keccak256("SetFeeRate(uint256 feeRate,uint256 nonce)");

    /*=========================== 3. STATE VARIABLES =========================*/
    address private _genesisSigner;
    bytes32 private _genesisValidator;
    uint256 private _totalWeight;
    uint256 private _weightedGasPrice;
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
    event WeightedGasPriceUpdated(uint256 previousPrice, uint256 newPrice);
    event TotalWeightUpdated(uint256 previousWeight, uint256 newWeight);

    /*=========================== 5. MODIFIERS ===============================*/
    modifier onlySigner(address signer) {
        // solhint-disable-next-line avoid-tx-origin
        if (msg.sender != signer || tx.origin != signer) revert NotCalledBySigner();
        _;
    }

    /*=========================== 6. FUNCTIONS ===============================*/
    constructor(bytes32 genesisValidator, address genesisSigner) {
        _feeRate = 21000;
        _genesisSigner = genesisSigner;
        _genesisValidator = genesisValidator;
    }

    function setFeeRate(
        uint256 feeRate,
        uint256 nonce,
        bytes calldata signatures
    ) external nonReentrant whenNotPaused useNonce(nonce) coreContractValid {
        if (!verify(keccak256(abi.encode(_SET_FEE_RATE_TYPEHASH, feeRate, nonce)), signatures)) {
            revert VerificationFailed();
        }
        _feeRate = feeRate;
        emit FeeRateUpdated(feeRate, nonce);
        IVerifier(coreContract()).setFee(feeRate * _weightedGasPrice);
    }

    function submitValidator(
        bytes32 validator,
        address signer,
        uint256 weight,
        uint32 epoch,
        address rewardTo,
        bytes calldata signatures
    ) external nonReentrant whenNotPaused onlySigner(signer) coreContractValid {
        {
            // Statck too deep
            bytes32 structHash = keccak256(
                abi.encode(_SUBMIT_VALIDATOR_TYPEHASH, validator, signer, weight, epoch)
            );
            if (!verify(structHash, signatures)) revert VerificationFailed();
        }
        if (validator == bytes32(0) || validator == _genesisValidator) revert InvalidValidator();
        if (signer == address(0) || signer == _genesisSigner) revert InvalidSigner();

        ValidatorInfo memory info = _validatorInfos[validator];
        if (epoch < info.epoch || epoch != _getCurrentEpoch()) revert InvalidEpoch();

        uint256 totalWeight = _totalWeight;
        uint256 weightClear = _revokeSubmission(validator, info, false);
        if (!_inRewardTimeRange(info) || info.epoch == epoch) {
            weightClear = 0;
        }

        if (_signerToValidator[signer] != bytes32(0)) revert SignerReferencedByOtherValidator();
        if (_weights[signer] != 0) revert SignerWeightNotCleared();

        if (info.epoch == 0) {
            _validators.push(validator);
        }

        info.gasPrice = tx.gasprice;
        info.signer = signer;
        // solhint-disable-next-line not-rely-on-time
        info.lastSubmit = uint64(block.timestamp);
        info.epoch = epoch;
        _doSubmission(validator, info, weight);

        if (weightClear != 0 && rewardTo != address(0)) {
            _sendReward(rewardTo, weightClear, totalWeight);
        }
    }

    function purgeValidators(bytes32[] calldata validators, address rewardTo)
        external
        nonReentrant
        whenNotPaused
        coreContractValid
    {
        if (!_inPurgeTimeRange()) revert NotInPurgeTimeRange();
        uint256 totalWeight = _totalWeight;
        uint256 weight = 0;
        for (uint256 i = 0; i < validators.length; ) {
            bytes32 validator = validators[i];
            ValidatorInfo memory info = _validatorInfos[validator];
            if (_canPurge(info)) {
                weight += _revokeSubmission(validator, info, true);
            }
            unchecked {
                ++i;
            }
        }

        if (weight != 0 && rewardTo != address(0)) {
            _sendReward(rewardTo, weight, totalWeight);
        }
    }

    function getGenesisValidator() external view returns (bytes32) {
        return _genesisValidator;
    }

    function getGenesisSigner() external view returns (address) {
        return _genesisSigner;
    }

    function getWeight(address signer) external view returns (uint256) {
        return _getWeight(signer, _genesisSigner, _totalWeight);
    }

    function getFeeRate() external view returns (uint256) {
        return _feeRate;
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

    function getValidators(uint256 begin, uint256 end)
        external
        view
        returns (ValidatorFullInfo[] memory)
    {
        uint256 length = _validators.length;
        if (end > length) end = length;
        if (begin >= end) return new ValidatorFullInfo[](0);
        ValidatorFullInfo[] memory result = new ValidatorFullInfo[](end - begin);
        for ((uint256 i, uint256 j) = (begin, 0); i < end; ) {
            bytes32 validator = _validators[i];
            result[j].validator = validator;
            ValidatorInfo memory info = _validatorInfos[validator];
            result[j].gasPrice = info.gasPrice;
            result[j].signer = info.signer;
            result[j].lastSubmit = info.lastSubmit;
            result[j].epoch = info.epoch;
            result[j].weight = _weights[info.signer];
            unchecked {
                ++i;
                ++j;
            }
        }
        return result;
    }

    function getValidatorCount() external view returns (uint256) {
        return _validators.length;
    }

    function verify(bytes32 structHash, bytes calldata signatures) public view returns (bool) {
        bytes32 typedHash = _hashTypedDataV4(structHash);
        return verifyTypedData(typedHash, signatures);
    }

    function verifyTypedData(bytes32 typedHash, bytes calldata signatures)
        public
        view
        returns (bool)
    {
        uint256 length = signatures.length;
        if (length == 0 || length % 65 != 0) revert InvalidSignatures();
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

        for (i = 0; i < count; ) {
            (r, s, v) = _decodeSignature(signatures, i);
            current = ecrecover(typedHash, v, r, s);
            if (current == address(0)) revert EcrecoverFailed();
            if (current <= last) revert InvalidSignerOrder();
            last = current;
            weight += _getWeight(current, genesis, total);
            unchecked {
                ++i;
            }
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
        // solhint-disable-next-line not-rely-on-time
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
        // solhint-disable-next-line not-rely-on-time
        return (block.timestamp % epochTime) >= delay;
    }

    function _inPurgeTimeRange() internal view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
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
    ) private returns (uint256) {
        address signer = info.signer;
        if (signer == address(0)) {
            return 0;
        }
        _signerToValidator[signer] = bytes32(0);
        uint256 weight = _weights[signer];
        _weights[signer] = 0;
        _decreaseTotalWeightAndUpdateGasPrice(weight, info.gasPrice);

        info.gasPrice = 0;
        info.signer = address(0);
        if (store) {
            _validatorInfos[validator] = info;
            emit ValidatorPurged(validator, signer, weight, info.epoch);
        }
        return weight;
    }

    function _sendReward(
        address to,
        uint256 weight,
        uint256 totalWeight
    ) private {
        if (weight == 0) {
            return;
        }
        uint256 share = _REWARD_FACTOR;
        if (weight < totalWeight) {
            share = (_REWARD_FACTOR * weight) / totalWeight;
        }
        IVerifier(coreContract()).sendReward(to, share);
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
        _updateWeightedGasPrice(newPrice);
    }

    function _decreaseTotalWeightAndUpdateGasPrice(uint256 weight, uint256 gasPrice) private {
        if (weight == 0) {
            return;
        }

        uint256 currentWeight = _totalWeight;
        if (weight >= currentWeight) {
            _totalWeight = 0;
            emit TotalWeightUpdated(currentWeight, 0);
            _updateWeightedGasPrice(0);
            return;
        }

        uint256 newWeight = currentWeight - weight;
        _totalWeight = newWeight;
        emit TotalWeightUpdated(currentWeight, newWeight);

        uint256 currentPrice = _weightedGasPrice;
        uint256 removalPrice = (gasPrice * weight) / currentWeight;
        if (removalPrice >= currentPrice) {
            _updateWeightedGasPrice(0);
            return;
        }

        uint256 newPrice = ((currentPrice - removalPrice) * currentWeight) / newWeight;
        _updateWeightedGasPrice(newPrice);
    }

    function _updateWeightedGasPrice(uint256 price) private {
        uint256 currentPrice = _weightedGasPrice;
        if (currentPrice == price) {
            return;
        }

        _weightedGasPrice = price;
        emit WeightedGasPriceUpdated(currentPrice, price);
        IVerifier(coreContract()).setFee(_feeRate * price);
    }
}
