// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {EIP7702Helper} from "./EIP7702Helper.sol";
import {Auth7702} from "./Auth7702.sol";

/// @title SessionKeyHelper
/// @notice High-level helpers for session key testing on top of EIP7702Helper.
///         Handles SessionConfig construction, ExecutionRequest signing (raw + EIP-712),
///         and batch execution.
/// @dev    Inheritance chain:
///           forge-std/Test  ←  EIP7702Helper  ←  SessionKeyHelper  ←  YourTest
abstract contract SessionKeyHelper is EIP7702Helper {

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice Defines what a session key is allowed to do.
    /// @param sessionKey   The address of the session key (derived from sessionKeyPk).
    /// @param target       The only contract this session key may call.
    /// @param selector     The only function selector this session key may call.
    /// @param tokenIn      Input token address (address(0) = ETH or not applicable).
    /// @param tokenOut     Output token address (address(0) = not applicable).
    /// @param maxAmount    Maximum token amount per execution.
    /// @param validAfter   Timestamp after which the session is active.
    /// @param validUntil   Timestamp after which the session expires.
    /// @param maxCalls     Maximum number of times this session key may be used (0 = unlimited).
    struct SessionConfig {
        address sessionKey;
        address target;
        bytes4  selector;
        address tokenIn;
        address tokenOut;
        uint256 maxAmount;
        uint48  validAfter;
        uint48  validUntil;
        uint256 maxCalls;
    }

    /// @notice A single call inside an execution request.
    /// @param target    Contract to call.
    /// @param value     ETH value to send.
    /// @param data      Calldata.
    struct Call {
        address target;
        uint256 value;
        bytes   data;
    }

    /// @notice A signed execution request from a session key.
    /// @param calls     Batch of calls to execute.
    /// @param nonce     Session nonce — prevents replay within the session.
    /// @param deadline  Timestamp after which this request is invalid.
    struct ExecutionRequest {
        Call[]  calls;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice A signed execution request ready to submit.
    struct SignedExecutionRequest {
        ExecutionRequest req;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    // -------------------------------------------------------------------------
    // EIP-712 Domain
    // -------------------------------------------------------------------------

    bytes32 private constant _DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant _SESSION_CONFIG_TYPEHASH = keccak256(
        "SessionConfig(address sessionKey,address target,bytes4 selector,address tokenIn,address tokenOut,uint256 maxAmount,uint48 validAfter,uint48 validUntil,uint256 maxCalls)"
    );

    bytes32 private constant _CALL_TYPEHASH = keccak256(
        "Call(address target,uint256 value,bytes data)"
    );

    bytes32 private constant _EXECUTION_REQUEST_TYPEHASH = keccak256(
        "ExecutionRequest(Call[] calls,uint256 nonce,uint256 deadline)Call(address target,uint256 value,bytes data)"
    );

    // -------------------------------------------------------------------------
    // Session Config
    // -------------------------------------------------------------------------

    /// @notice Builds a fully populated SessionConfig struct.
    /// @param sessionKeyPk  Private key of the session key — address is derived.
    /// @param target        Contract the session key may call.
    /// @param selector      Function selector the session key may call.
    /// @param tokenIn       Input token (address(0) if not applicable).
    /// @param tokenOut      Output token (address(0) if not applicable).
    /// @param maxAmount     Max token amount per call.
    /// @param duration      Session duration in seconds from now.
    /// @param maxCalls      Max number of calls allowed (0 = unlimited).
    /// @return config       The populated SessionConfig.
    function buildSessionConfig(
        uint256 sessionKeyPk,
        address target,
        bytes4  selector,
        address tokenIn,
        address tokenOut,
        uint256 maxAmount,
        uint256 duration,
        uint256 maxCalls
    ) internal view returns (SessionConfig memory config) {
        config = SessionConfig({
            sessionKey:  vm.addr(sessionKeyPk),
            target:      target,
            selector:    selector,
            tokenIn:     tokenIn,
            tokenOut:    tokenOut,
            maxAmount:   maxAmount,
            validAfter:  uint48(block.timestamp),
            validUntil:  uint48(block.timestamp + duration),
            maxCalls:    maxCalls
        });
    }

    // -------------------------------------------------------------------------
    // Execution Request builders
    // -------------------------------------------------------------------------

    /// @notice Builds a single-call ExecutionRequest.
    function buildExecutionRequest(
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (ExecutionRequest memory req) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: target, value: value, data: data});
        req = ExecutionRequest({calls: calls, nonce: nonce, deadline: deadline});
    }

    /// @notice Builds a multi-call (batch) ExecutionRequest.
    function buildBatchExecutionRequest(
        Call[] memory calls,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (ExecutionRequest memory req) {
        req = ExecutionRequest({calls: calls, nonce: nonce, deadline: deadline});
    }

    // -------------------------------------------------------------------------
    // Signing — Raw keccak256
    // -------------------------------------------------------------------------

    /// @notice Signs an ExecutionRequest using raw keccak256 (no EIP-712).
    ///         Hash: keccak256(abi.encode(calls, nonce, deadline))
    /// @param sessionKeyPk  Private key of the session key.
    /// @param req           The execution request to sign.
    /// @return              A fully populated SignedExecutionRequest.
    function signExecutionRequest(
        uint256 sessionKeyPk,
        ExecutionRequest memory req
    ) internal pure returns (SignedExecutionRequest memory) {
        bytes32 hash = _hashExecutionRequestRaw(req);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPk, hash);
        return SignedExecutionRequest({req: req, v: v, r: r, s: s});
    }

    /// @notice Returns the raw keccak256 hash of an ExecutionRequest.
    function _hashExecutionRequestRaw(
        ExecutionRequest memory req
    ) internal pure returns (bytes32) {
        bytes32[] memory callHashes = new bytes32[](req.calls.length);
        for (uint256 i = 0; i < req.calls.length; i++) {
            callHashes[i] = keccak256(abi.encode(
                req.calls[i].target,
                req.calls[i].value,
                keccak256(req.calls[i].data)
            ));
        }
        return keccak256(abi.encode(
            keccak256(abi.encodePacked(callHashes)),
            req.nonce,
            req.deadline
        ));
    }

    // -------------------------------------------------------------------------
    // Signing — EIP-712
    // -------------------------------------------------------------------------

    /// @notice Signs an ExecutionRequest using EIP-712 typed structured data.
    /// @param sessionKeyPk    Private key of the session key.
    /// @param req             The execution request to sign.
    /// @param domainSeparator The EIP-712 domain separator of the verifying contract.
    /// @return                A fully populated SignedExecutionRequest.
    function signExecutionRequest712(
        uint256 sessionKeyPk,
        ExecutionRequest memory req,
        bytes32 domainSeparator
    ) internal pure returns (SignedExecutionRequest memory) {
        bytes32 structHash = _hashExecutionRequest712(req);
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPk, digest);
        return SignedExecutionRequest({req: req, v: v, r: r, s: s});
    }

    /// @notice Builds an EIP-712 domain separator for a verifying contract.
    /// @param name        Protocol name (e.g. "MyWallet").
    /// @param version     Protocol version (e.g. "1").
    /// @param verifier    The contract that will verify the signature (usually the EOA).
    function buildDomainSeparator(
        string memory name,
        string memory version,
        address verifier
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            _DOMAIN_TYPEHASH,
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            block.chainid,
            verifier
        ));
    }

    /// @notice Returns the EIP-712 struct hash of an ExecutionRequest.
    function _hashExecutionRequest712(
        ExecutionRequest memory req
    ) internal pure returns (bytes32) {
        bytes32[] memory callHashes = new bytes32[](req.calls.length);
        for (uint256 i = 0; i < req.calls.length; i++) {
            callHashes[i] = keccak256(abi.encode(
                _CALL_TYPEHASH,
                req.calls[i].target,
                req.calls[i].value,
                keccak256(req.calls[i].data)
            ));
        }
        return keccak256(abi.encode(
            _EXECUTION_REQUEST_TYPEHASH,
            keccak256(abi.encodePacked(callHashes)),
            req.nonce,
            req.deadline
        ));
    }

    /// @notice Returns the EIP-712 struct hash of a SessionConfig.
    function hashSessionConfig(SessionConfig memory config) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _SESSION_CONFIG_TYPEHASH,
            config.sessionKey,
            config.target,
            config.selector,
            config.tokenIn,
            config.tokenOut,
            config.maxAmount,
            config.validAfter,
            config.validUntil,
            config.maxCalls
        ));
    }

    // -------------------------------------------------------------------------
    // Calldata encoding
    // -------------------------------------------------------------------------

    /// @notice Encodes a single call into bytes for use in ExecutionRequest.
    function encodeExecution(
        address target,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(target, data);
    }

    /// @notice Encodes a batch of calls into bytes.
    function encodeBatch(Call[] memory calls) internal pure returns (bytes memory) {
        return abi.encode(calls);
    }

    // -------------------------------------------------------------------------
    // Validation helpers (for test assertions)
    // -------------------------------------------------------------------------

    /// @notice Returns true if a session config is currently active (within time window).
    function isSessionActive(SessionConfig memory config) internal view returns (bool) {
        return block.timestamp >= config.validAfter && block.timestamp < config.validUntil;
    }

    /// @notice Returns true if an execution request has not expired.
    function isRequestValid(ExecutionRequest memory req) internal view returns (bool) {
        return block.timestamp <= req.deadline;
    }

    /// @notice Recovers the signer address from a raw-signed ExecutionRequest.
    function recoverSigner(
        SignedExecutionRequest memory signed
    ) internal pure returns (address) {
        bytes32 hash = _hashExecutionRequestRaw(signed.req);
        return ecrecover(hash, signed.v, signed.r, signed.s);
    }

    /// @notice Recovers the signer address from an EIP-712 signed ExecutionRequest.
    function recoverSigner712(
        SignedExecutionRequest memory signed,
        bytes32 domainSeparator
    ) internal pure returns (address) {
        bytes32 structHash = _hashExecutionRequest712(signed.req);
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
        return ecrecover(digest, signed.v, signed.r, signed.s);
    }
}