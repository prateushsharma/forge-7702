// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {Auth7702} from "./Auth7702.sol";

/// @title EIP7702Helper
/// @notice Core helper contract for testing EIP-7702 delegation in Foundry.
///         Inherit this in your test contracts — it wraps all the boilerplate.
/// @dev    Inheritance chain:
///           forge-std/Test  ←  EIP7702Helper  ←  YourTest
abstract contract EIP7702Helper is Test {

    // -------------------------------------------------------------------------
    // Delegation
    // -------------------------------------------------------------------------

    /// @notice Delegates an EOA (derived from pk) to a logic contract.
    ///         Uses vm.etch to simulate the EIP-7702 delegation pointer in Foundry.
    ///         Delegation pointer format: 0xef0100 ++ address(logic)  (23 bytes)
    /// @param pk     Private key of the EOA owner.
    /// @param logic  Logic contract to delegate to.
    /// @return eoa   The EOA address derived from pk.
    function delegate(uint256 pk, address logic) internal returns (address eoa) {
        require(logic != address(0), "EIP7702Helper: logic cannot be zero address");
        eoa = vm.addr(pk);
        bytes memory delegationCode = abi.encodePacked(hex"ef0100", logic);
        vm.etch(eoa, delegationCode);
    }

    /// @notice Revokes delegation from an EOA by clearing its code.
    /// @param pk  Private key of the EOA owner.
    function revoke(uint256 pk) internal {
        address eoa = vm.addr(pk);
        vm.etch(eoa, "");
    }

    /// @notice Re-delegates an EOA to a new logic contract in one call.
    /// @param pk       Private key of the EOA owner.
    /// @param newLogic New logic contract to delegate to.
    /// @return eoa     The EOA address.
    function redelegate(uint256 pk, address newLogic) internal returns (address eoa) {
        revoke(pk);
        eoa = delegate(pk, newLogic);
    }

    // -------------------------------------------------------------------------
    // Inspection
    // -------------------------------------------------------------------------

    /// @notice Returns true if the EOA is currently delegated to the given logic contract.
    /// @param eoa    The EOA address to inspect.
    /// @param logic  The expected logic contract.
    function isDelegatedTo(address eoa, address logic) internal view returns (bool) {
        bytes memory code = eoa.code;
        if (code.length != 23) return false;
        if (code[0] != 0xef || code[1] != 0x01 || code[2] != 0x00) return false;
        address embedded;
        assembly {
            embedded := shr(96, mload(add(add(code, 0x20), 3)))
        }
        return embedded == logic;
    }

    /// @notice Returns true if the EOA has any active delegation.
    /// @param eoa  The EOA address to inspect.
    function isDelegated(address eoa) internal view returns (bool) {
        bytes memory code = eoa.code;
        if (code.length != 23) return false;
        return code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }

    /// @notice Returns the logic contract an EOA is currently delegated to.
    ///         Returns address(0) if not delegated.
    /// @param eoa  The EOA address to inspect.
    function getDelegatedLogic(address eoa) internal view returns (address logic) {
        if (!isDelegated(eoa)) return address(0);
        bytes memory code = eoa.code;
        assembly {
            logic := shr(96, mload(add(add(code, 0x20), 3)))
        }
    }

    // -------------------------------------------------------------------------
    // Signing
    // -------------------------------------------------------------------------

    /// @notice Signs an EIP-7702 authorization tuple.
    ///         Hash: keccak256(0x05 ++ rlp([chainId, address, nonce]))
    /// @param pk       Private key of the EOA owner.
    /// @param logic    Logic contract address to authorize.
    /// @param nonce    Current nonce of the EOA.
    /// @param chainId  Chain ID (pass 0 for chain-agnostic).
    /// @return         A fully populated SignedAuthorization.
    function signAuthorization(
        uint256 pk,
        address logic,
        uint256 nonce,
        uint256 chainId
    ) internal pure returns (Auth7702.SignedAuthorization memory) {
        Auth7702.Authorization memory auth = Auth7702.Authorization({
            chainId: chainId,
            logicContract: logic,
            nonce: nonce
        });
        bytes32 hash = Auth7702.hashAuthorization(auth);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        return Auth7702.SignedAuthorization({auth: auth, v: v, r: r, s: s});
    }

    /// @notice Convenience overload — uses block.chainid automatically.
    function signAuthorization(
        uint256 pk,
        address logic,
        uint256 nonce
    ) internal view returns (Auth7702.SignedAuthorization memory) {
        return signAuthorization(pk, logic, nonce, block.chainid);
    }

    // -------------------------------------------------------------------------
    // Execution helpers
    // -------------------------------------------------------------------------

    /// @notice Executes a call as the EOA (via vm.prank).
    ///         Requires the EOA to already be delegated.
    /// @param pk      Private key of the EOA — used to derive address.
    /// @param target  Contract to call.
    /// @param data    Calldata to send.
    /// @return ret    Raw return bytes.
    function executeAs(
        uint256 pk,
        address target,
        bytes memory data
    ) internal returns (bytes memory ret) {
        address eoa = vm.addr(pk);
        require(isDelegated(eoa), "EIP7702Helper: EOA is not delegated");
        vm.prank(eoa);
        (bool ok, bytes memory result) = target.call(data);
        require(ok, "EIP7702Helper: call failed");
        return result;
    }

    /// @notice Same as executeAs but with ETH value.
    function executeAs(
        uint256 pk,
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory ret) {
        address eoa = vm.addr(pk);
        require(isDelegated(eoa), "EIP7702Helper: EOA is not delegated");
        vm.deal(eoa, eoa.balance + value);
        vm.prank(eoa);
        (bool ok, bytes memory result) = target.call{value: value}(data);
        require(ok, "EIP7702Helper: call failed");
        return result;
    }
}