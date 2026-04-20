// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

/// @title Auth7702
/// @notice Foundation library for EIP-7702 authorization structs and signing hashes.
///         All other forge-7702 contracts import from here.
/// @dev    EIP-7702 signing scheme:
///           hash = keccak256(0x05 ++ rlp([chainId, address, nonce]))
///         This is distinct from EIP-712 and standard transaction signing.
library Auth7702 {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice EIP-7702 domain magic byte prepended before the RLP payload.
    uint8 internal constant MAGIC = 0x05;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice The unsigned authorization tuple.
    /// @param chainId        The chain this authorization is valid on (0 = any chain).
    /// @param logicContract  The contract the EOA will delegate execution to.
    /// @param nonce          Current nonce of the EOA at signing time (prevents replay).
    struct Authorization {
        uint256 chainId;
        address logicContract;
        uint256 nonce;
    }

    /// @notice A signed authorization — Authorization + ECDSA signature components.
    /// @param auth  The unsigned authorization tuple.
    /// @param v     Recovery identifier (27 or 28).
    /// @param r     ECDSA signature r component.
    /// @param s     ECDSA signature s component.
    struct SignedAuthorization {
        Authorization auth;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // -------------------------------------------------------------------------
    // Hashing
    // -------------------------------------------------------------------------

    /// @notice Produces the EIP-7702 signing hash for an Authorization tuple.
    ///         Formula: keccak256(0x05 ++ rlp([chainId, address, nonce]))
    /// @param auth  The authorization to hash.
    /// @return      The hash that the EOA owner must sign.
    function hashAuthorization(Authorization memory auth) internal pure returns (bytes32) {
        bytes memory encoded = _rlpEncodeAuthorization(auth.chainId, auth.logicContract, auth.nonce);
        return keccak256(abi.encodePacked(MAGIC, encoded));
    }

    /// @notice Convenience overload — hash directly from components.
    function hashAuthorization(
        uint256 chainId,
        address logicContract,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return hashAuthorization(Authorization(chainId, logicContract, nonce));
    }

    // -------------------------------------------------------------------------
    // RLP Encoding (internal)
    // -------------------------------------------------------------------------

    /// @dev RLP-encodes the three-element list [chainId, address, nonce].
    function _rlpEncodeAuthorization(
        uint256 chainId,
        address logicContract,
        uint256 nonce
    ) private pure returns (bytes memory) {
        bytes memory encodedChainId = _rlpEncodeUint(chainId);
        bytes memory encodedAddress = _rlpEncodeAddress(logicContract);
        bytes memory encodedNonce   = _rlpEncodeUint(nonce);

        uint256 payloadLen = encodedChainId.length + encodedAddress.length + encodedNonce.length;
        bytes memory listPrefix = _rlpListPrefix(payloadLen);

        return abi.encodePacked(listPrefix, encodedChainId, encodedAddress, encodedNonce);
    }

    /// @dev RLP encodes a uint256.
    ///      - 0        → 0x80
    ///      - 0x01–0x7f → single byte
    ///      - else      → 0x80+len prefix + big-endian bytes
    function _rlpEncodeUint(uint256 value) private pure returns (bytes memory) {
        if (value == 0) {
            return abi.encodePacked(uint8(0x80));
        }
        bytes memory be = _toBigEndian(value);
        if (be.length == 1 && uint8(be[0]) < 0x80) {
            return be;
        }
        return abi.encodePacked(uint8(0x80 + be.length), be);
    }

    /// @dev RLP encodes an Ethereum address (always 20 bytes → 0x94 prefix).
    function _rlpEncodeAddress(address addr) private pure returns (bytes memory) {
        return abi.encodePacked(uint8(0x94), addr);
    }

    /// @dev Returns the RLP list prefix for a given payload length.
    function _rlpListPrefix(uint256 length) private pure returns (bytes memory) {
        if (length <= 55) {
            return abi.encodePacked(uint8(0xc0 + length));
        }
        bytes memory beLen = _toBigEndian(length);
        return abi.encodePacked(uint8(0xf7 + beLen.length), beLen);
    }

    /// @dev Minimal big-endian encoding of a uint256 (no leading zeros).
    function _toBigEndian(uint256 value) private pure returns (bytes memory) {
        bytes memory b = abi.encodePacked(value);
        uint256 i = 0;
        while (i < 32 && b[i] == 0) i++;
        bytes memory result = new bytes(32 - i);
        for (uint256 j = 0; j < result.length; j++) {
            result[j] = b[i + j];
        }
        return result;
    }
}