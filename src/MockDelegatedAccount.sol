// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {EIP7702Helper} from "./EIP7702Helper.sol";

/// @title MockDelegatedAccount
/// @notice A drop-in mock EOA for tests that don't need real private keys.
///         Useful for quick unit tests that just need a delegated account to exist.
/// @dev    Does not use real EIP-7702 signing — uses vm.etch directly.
///         For tests that need real signed authorizations, use EIP7702Helper directly.
///
/// Usage:
///
///   contract MyTest is Test {
///       MockDelegatedAccount mock;
///
///       function setUp() public {
///           mock = new MockDelegatedAccount();
///           mock.simulateDelegate(address(myLogic));
///       }
///
///       function test_something() public {
///           mock.executeAs(address(myLogic), abi.encodeCall(IWallet.execute, (...)));
///       }
///   }
contract MockDelegatedAccount is EIP7702Helper {

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice The address of this mock EOA.
    ///         Set once at construction — this is the address that gets etched.
    address public immutable eoa;

    /// @dev Internal private key — deterministic, never used for real signing.
    ///      Just used to derive a stable address via vm.addr().
    uint256 private immutable _pk;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param pk  A deterministic private key to derive the mock EOA address from.
    ///            Suggestion: pass a labeled constant like uint256(keccak256("mock.eoa")).
    constructor(uint256 pk) {
        require(pk != 0, "MockDelegatedAccount: pk cannot be zero");
        _pk = pk;
        eoa = vm.addr(pk);
    }

    // -------------------------------------------------------------------------
    // Delegation simulation
    // -------------------------------------------------------------------------

    /// @notice Simulates delegation by etching the delegation pointer onto the EOA.
    ///         No signing required — purely for test setup convenience.
    /// @param logic  The logic contract to delegate to.
    function simulateDelegate(address logic) external {
        delegate(_pk, logic);
    }

    /// @notice Simulates revocation by clearing the EOA's code.
    function simulateRevoke() external {
        revoke(_pk);
    }

    /// @notice Simulates re-delegation to a new logic contract.
    /// @param newLogic  The new logic contract to delegate to.
    function simulateRedelegate(address newLogic) external {
        redelegate(_pk, newLogic);
    }

    // -------------------------------------------------------------------------
    // Execution
    // -------------------------------------------------------------------------

    /// @notice Executes a call as the mock EOA.
    ///         EOA must be delegated first via simulateDelegate().
    /// @param target  Contract to call.
    /// @param data    Calldata to send.
    /// @return        Raw return bytes.
    function executeAs(address target, bytes calldata data) external returns (bytes memory) {
        return executeAs(_pk, target, data);
    }

    /// @notice Executes a call as the mock EOA with ETH value.
    /// @param target  Contract to call.
    /// @param data    Calldata to send.
    /// @param value   ETH to send with the call.
    /// @return        Raw return bytes.
    function executeAs(
        address target,
        bytes calldata data,
        uint256 value
    ) external returns (bytes memory) {
        return executeAs(_pk, target, data, value);
    }

    // -------------------------------------------------------------------------
    // Inspection helpers
    // -------------------------------------------------------------------------

    /// @notice Returns true if this mock EOA is currently delegated to the given logic.
    function isDelegatedTo(address logic) external view returns (bool) {
        return isDelegatedTo(eoa, logic);
    }

    /// @notice Returns true if this mock EOA has any active delegation.
    function isDelegated() external view returns (bool) {
        return isDelegated(eoa);
    }

    /// @notice Returns the logic contract this mock EOA is currently delegated to.
    ///         Returns address(0) if not delegated.
    function getDelegatedLogic() external view returns (address) {
        return getDelegatedLogic(eoa);
    }
}