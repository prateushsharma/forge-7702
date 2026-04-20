// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {EIP7702Helper} from "../src/EIP7702Helper.sol";
import {SessionKeyHelper} from "../src/SessionKeyHelper.sol";
import {MockDelegatedAccount} from "../src/MockDelegatedAccount.sol";
import {Auth7702} from "../src/Auth7702.sol";

// -------------------------------------------------------------------------
// Minimal logic contract for delegation tests
// -------------------------------------------------------------------------

contract SimpleLogic {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function getValue() external view returns (uint256) {
        return value;
    }
}

// -------------------------------------------------------------------------
// Minimal logic contract for session key tests
// -------------------------------------------------------------------------

contract TokenSwapLogic {
    event SwapExecuted(address indexed sessionKey, uint256 amount);

    function swap(uint256 amount) external {
        emit SwapExecuted(msg.sender, amount);
    }
}

// -------------------------------------------------------------------------
// Main test suite
// -------------------------------------------------------------------------

contract EIP7702HelperTest is Test, SessionKeyHelper {

    // Private keys — never use these outside tests
    uint256 constant OWNER_PK       = uint256(keccak256("owner"));
    uint256 constant SESSION_KEY_PK = uint256(keccak256("sessionKey"));
    uint256 constant MOCK_PK        = uint256(keccak256("mock.eoa"));

    // Addresses derived from keys
    address owner;
    address sessionKeyAddr;

    // Contracts
    SimpleLogic    simpleLogic;
    TokenSwapLogic swapLogic;
    MockDelegatedAccount mock;

    function setUp() public {
        owner         = vm.addr(OWNER_PK);
        sessionKeyAddr = vm.addr(SESSION_KEY_PK);

        simpleLogic = new SimpleLogic();
        swapLogic   = new TokenSwapLogic();
        mock        = new MockDelegatedAccount(MOCK_PK);
    }

    // =========================================================================
    // Auth7702 — hashing
    // =========================================================================

    function test_hashAuthorization_notZero() public {
        Auth7702.Authorization memory auth = Auth7702.Authorization({
            chainId:      block.chainid,
            logicContract: address(simpleLogic),
            nonce:        0
        });
        bytes32 hash = Auth7702.hashAuthorization(auth);
        assertNotEq(hash, bytes32(0));
    }

    function test_hashAuthorization_componentOverload_matches() public {
        Auth7702.Authorization memory auth = Auth7702.Authorization({
            chainId:      block.chainid,
            logicContract: address(simpleLogic),
            nonce:        1
        });
        bytes32 hashA = Auth7702.hashAuthorization(auth);
        bytes32 hashB = Auth7702.hashAuthorization(block.chainid, address(simpleLogic), 1);
        assertEq(hashA, hashB);
    }

    function test_hashAuthorization_differentNonce_differentHash() public {
        bytes32 hashA = Auth7702.hashAuthorization(block.chainid, address(simpleLogic), 0);
        bytes32 hashB = Auth7702.hashAuthorization(block.chainid, address(simpleLogic), 1);
        assertNotEq(hashA, hashB);
    }

    function test_hashAuthorization_differentLogic_differentHash() public {
        bytes32 hashA = Auth7702.hashAuthorization(block.chainid, address(simpleLogic), 0);
        bytes32 hashB = Auth7702.hashAuthorization(block.chainid, address(swapLogic), 0);
        assertNotEq(hashA, hashB);
    }

    function test_hashAuthorization_zeroChainId_allowed() public {
        bytes32 hash = Auth7702.hashAuthorization(0, address(simpleLogic), 0);
        assertNotEq(hash, bytes32(0));
    }

    // =========================================================================
    // EIP7702Helper — delegation
    // =========================================================================

    function test_delegate_setsCode() public {
        address eoa = delegate(OWNER_PK, address(simpleLogic));
        assertEq(eoa, owner);
        assertTrue(eoa.code.length == 23);
    }

    function test_delegate_correctPointer() public {
        address eoa = delegate(OWNER_PK, address(simpleLogic));
        bytes memory code = eoa.code;
       assertEq(code[0], bytes1(0xef));
        assertEq(code[1], bytes1(0x01));
        assertEq(code[2], bytes1(0x00));
    }

    function test_delegate_revertsOnZeroAddress() public {
        vm.expectRevert("EIP7702Helper: logic cannot be zero address");
        delegate(OWNER_PK, address(0));
    }

    function test_isDelegatedTo_true() public {
        address eoa = delegate(OWNER_PK, address(simpleLogic));
        assertTrue(isDelegatedTo(eoa, address(simpleLogic)));
    }

    function test_isDelegatedTo_false_wrongLogic() public {
        address eoa = delegate(OWNER_PK, address(simpleLogic));
        assertFalse(isDelegatedTo(eoa, address(swapLogic)));
    }

    function test_isDelegated_true() public {
        address eoa = delegate(OWNER_PK, address(simpleLogic));
        assertTrue(isDelegated(eoa));
    }

    function test_isDelegated_false_beforeDelegate() public {
        assertFalse(isDelegated(owner));
    }

    function test_getDelegatedLogic_returnsCorrectAddress() public {
        address eoa = delegate(OWNER_PK, address(simpleLogic));
        assertEq(getDelegatedLogic(eoa), address(simpleLogic));
    }

    function test_getDelegatedLogic_returnsZero_whenNotDelegated() public {
        assertEq(getDelegatedLogic(owner), address(0));
    }

    // =========================================================================
    // EIP7702Helper — revocation
    // =========================================================================

    function test_revoke_clearsCode() public {
        delegate(OWNER_PK, address(simpleLogic));
        revoke(OWNER_PK);
        assertFalse(isDelegated(owner));
        assertEq(owner.code.length, 0);
    }

    function test_revoke_getDelegatedLogic_returnsZero() public {
        delegate(OWNER_PK, address(simpleLogic));
        revoke(OWNER_PK);
        assertEq(getDelegatedLogic(owner), address(0));
    }

    // =========================================================================
    // EIP7702Helper — redelegation
    // =========================================================================

    function test_redelegate_updatesLogic() public {
        delegate(OWNER_PK, address(simpleLogic));
        address eoa = redelegate(OWNER_PK, address(swapLogic));
        assertTrue(isDelegatedTo(eoa, address(swapLogic)));
        assertFalse(isDelegatedTo(eoa, address(simpleLogic)));
    }

    function test_redelegate_returnsCorrectEoa() public {
        address eoa = redelegate(OWNER_PK, address(swapLogic));
        assertEq(eoa, owner);
    }

    // =========================================================================
    // EIP7702Helper — signing
    // =========================================================================

    function test_signAuthorization_recoversCorrectSigner() public {
        Auth7702.SignedAuthorization memory signed = signAuthorization(
            OWNER_PK,
            address(simpleLogic),
            0,
            block.chainid
        );
        bytes32 hash = Auth7702.hashAuthorization(signed.auth);
        address recovered = ecrecover(hash, signed.v, signed.r, signed.s);
        assertEq(recovered, owner);
    }

    function test_signAuthorization_chainIdOverload_usesBlockChainId() public {
        Auth7702.SignedAuthorization memory signed = signAuthorization(
            OWNER_PK,
            address(simpleLogic),
            0
        );
        assertEq(signed.auth.chainId, block.chainid);
    }

    function test_signAuthorization_differentNonces_differentSigs() public {
        Auth7702.SignedAuthorization memory a = signAuthorization(OWNER_PK, address(simpleLogic), 0);
        Auth7702.SignedAuthorization memory b = signAuthorization(OWNER_PK, address(simpleLogic), 1);
        assertNotEq(a.r, b.r);
    }

    // =========================================================================
    // EIP7702Helper — executeAs
    // =========================================================================

    function test_executeAs_callsTarget() public {
        delegate(OWNER_PK, address(simpleLogic));
        bytes memory data = abi.encodeCall(SimpleLogic.setValue, (42));
        executeAs(OWNER_PK, address(simpleLogic), data);
        assertEq(simpleLogic.value(), 42);
    }

    function test_executeAs_revertsIfNotDelegated() public {
        vm.expectRevert("EIP7702Helper: EOA is not delegated");
        executeAs(OWNER_PK, address(simpleLogic), abi.encodeCall(SimpleLogic.setValue, (1)));
    }

    function test_executeAs_withValue_sendsEth() public {
        delegate(OWNER_PK, address(simpleLogic));
        uint256 balanceBefore = address(simpleLogic).balance;
        executeAs(OWNER_PK, address(simpleLogic), "", 1 ether);
        assertEq(address(simpleLogic).balance, balanceBefore + 1 ether);
    }

    // =========================================================================
    // MockDelegatedAccount
    // =========================================================================

    function test_mock_simulateDelegate_setsCode() public {
        mock.simulateDelegate(address(simpleLogic));
        assertTrue(mock.isDelegated());
    }

    function test_mock_isDelegatedTo_true() public {
        mock.simulateDelegate(address(simpleLogic));
        assertTrue(mock.isDelegatedTo(address(simpleLogic)));
    }

    function test_mock_isDelegatedTo_false_wrongLogic() public {
        mock.simulateDelegate(address(simpleLogic));
        assertFalse(mock.isDelegatedTo(address(swapLogic)));
    }

    function test_mock_simulateRevoke_clearsCode() public {
        mock.simulateDelegate(address(simpleLogic));
        mock.simulateRevoke();
        assertFalse(mock.isDelegated());
    }

    function test_mock_simulateRedelegate_updatesLogic() public {
        mock.simulateDelegate(address(simpleLogic));
        mock.simulateRedelegate(address(swapLogic));
        assertTrue(mock.isDelegatedTo(address(swapLogic)));
    }

    function test_mock_getDelegatedLogic_correct() public {
        mock.simulateDelegate(address(simpleLogic));
        assertEq(mock.getDelegatedLogic(), address(simpleLogic));
    }

    function test_mock_executeAs_callsTarget() public {
        mock.simulateDelegate(address(simpleLogic));
        bytes memory data = abi.encodeCall(SimpleLogic.setValue, (99));
        mock.executeAs(address(simpleLogic), data);
        assertEq(simpleLogic.value(), 99);
    }

    // =========================================================================
    // SessionKeyHelper — SessionConfig
    // =========================================================================

    function test_buildSessionConfig_correctFields() public {
        SessionKeyHelper.SessionConfig memory config = buildSessionConfig(
            SESSION_KEY_PK,
            address(swapLogic),
            TokenSwapLogic.swap.selector,
            address(0),
            address(0),
            1000e18,
            1 days,
            10
        );

        assertEq(config.sessionKey,  sessionKeyAddr);
        assertEq(config.target,      address(swapLogic));
        assertEq(config.selector,    TokenSwapLogic.swap.selector);
        assertEq(config.maxAmount,   1000e18);
        assertEq(config.maxCalls,    10);
        assertEq(config.validAfter,  uint48(block.timestamp));
        assertEq(config.validUntil,  uint48(block.timestamp + 1 days));
    }

    function test_isSessionActive_true() public {
        SessionKeyHelper.SessionConfig memory config = buildSessionConfig(
            SESSION_KEY_PK, address(swapLogic), TokenSwapLogic.swap.selector,
            address(0), address(0), 1000e18, 1 days, 10
        );
        assertTrue(isSessionActive(config));
    }

    function test_isSessionActive_false_afterExpiry() public {
        SessionKeyHelper.SessionConfig memory config = buildSessionConfig(
            SESSION_KEY_PK, address(swapLogic), TokenSwapLogic.swap.selector,
            address(0), address(0), 1000e18, 1 days, 10
        );
        vm.warp(block.timestamp + 2 days);
        assertFalse(isSessionActive(config));
    }

    function test_isSessionActive_false_beforeValidAfter() public {
        SessionKeyHelper.SessionConfig memory config = buildSessionConfig(
            SESSION_KEY_PK, address(swapLogic), TokenSwapLogic.swap.selector,
            address(0), address(0), 1000e18, 1 days, 10
        );
        // manually push validAfter into the future
        config.validAfter = uint48(block.timestamp + 1 hours);
        assertFalse(isSessionActive(config));
    }

    // =========================================================================
    // SessionKeyHelper — raw signing
    // =========================================================================

    function test_signExecutionRequest_raw_recoversSessionKey() public {
        SessionKeyHelper.ExecutionRequest memory req = buildExecutionRequest(
            address(swapLogic),
            0,
            abi.encodeCall(TokenSwapLogic.swap, (500e18)),
            0,
            block.timestamp + 1 hours
        );
        SignedExecutionRequest memory signed = signExecutionRequest(SESSION_KEY_PK, req);
        address recovered = recoverSigner(signed);
        assertEq(recovered, sessionKeyAddr);
    }

    function test_signExecutionRequest_raw_isRequestValid_true() public {
        ExecutionRequest memory req = buildExecutionRequest(
            address(swapLogic), 0,
            abi.encodeCall(TokenSwapLogic.swap, (100e18)),
            0, block.timestamp + 1 hours
        );
        assertTrue(isRequestValid(req));
    }

    function test_signExecutionRequest_raw_isRequestValid_false_afterDeadline() public {
        ExecutionRequest memory req = buildExecutionRequest(
            address(swapLogic), 0,
            abi.encodeCall(TokenSwapLogic.swap, (100e18)),
            0, block.timestamp + 1 hours
        );
        vm.warp(block.timestamp + 2 hours);
        assertFalse(isRequestValid(req));
    }

    // =========================================================================
    // SessionKeyHelper — EIP-712 signing
    // =========================================================================

    function test_signExecutionRequest_712_recoversSessionKey() public {
        bytes32 domainSep = buildDomainSeparator("MyWallet", "1", address(swapLogic));

        ExecutionRequest memory req = buildExecutionRequest(
            address(swapLogic),
            0,
            abi.encodeCall(TokenSwapLogic.swap, (500e18)),
            0,
            block.timestamp + 1 hours
        );
        SignedExecutionRequest memory signed = signExecutionRequest712(SESSION_KEY_PK, req, domainSep);
        address recovered = recoverSigner712(signed, domainSep);
        assertEq(recovered, sessionKeyAddr);
    }

    function test_signExecutionRequest_712_differentDomain_differentSig() public {
        bytes32 domainA = buildDomainSeparator("WalletA", "1", address(swapLogic));
        bytes32 domainB = buildDomainSeparator("WalletB", "1", address(swapLogic));

        ExecutionRequest memory req = buildExecutionRequest(
            address(swapLogic), 0,
            abi.encodeCall(TokenSwapLogic.swap, (100e18)),
            0, block.timestamp + 1 hours
        );
        SignedExecutionRequest memory a = signExecutionRequest712(SESSION_KEY_PK, req, domainA);
        SignedExecutionRequest memory b = signExecutionRequest712(SESSION_KEY_PK, req, domainB);
        assertNotEq(a.r, b.r);
    }

    // =========================================================================
    // SessionKeyHelper — batch execution request
    // =========================================================================

    function test_buildBatchExecutionRequest_correctLength() public {
        SessionKeyHelper.Call[] memory calls = new SessionKeyHelper.Call[](3);
        calls[0] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (100e18))});
        calls[1] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (200e18))});
        calls[2] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (300e18))});

        ExecutionRequest memory req = buildBatchExecutionRequest(calls, 0, block.timestamp + 1 hours);
        assertEq(req.calls.length, 3);
    }

    function test_batchRequest_raw_recoversSessionKey() public {
        SessionKeyHelper.Call[] memory calls = new SessionKeyHelper.Call[](2);
        calls[0] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (100e18))});
        calls[1] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (200e18))});

        ExecutionRequest memory req = buildBatchExecutionRequest(calls, 1, block.timestamp + 1 hours);
        SignedExecutionRequest memory signed = signExecutionRequest(SESSION_KEY_PK, req);
        assertEq(recoverSigner(signed), sessionKeyAddr);
    }

    function test_batchRequest_712_recoversSessionKey() public {
        bytes32 domainSep = buildDomainSeparator("MyWallet", "1", address(swapLogic));

        SessionKeyHelper.Call[] memory calls = new SessionKeyHelper.Call[](2);
        calls[0] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (100e18))});
        calls[1] = SessionKeyHelper.Call({target: address(swapLogic), value: 0, data: abi.encodeCall(TokenSwapLogic.swap, (200e18))});

        ExecutionRequest memory req = buildBatchExecutionRequest(calls, 1, block.timestamp + 1 hours);
        SignedExecutionRequest memory signed = signExecutionRequest712(SESSION_KEY_PK, req, domainSep);
        assertEq(recoverSigner712(signed, domainSep), sessionKeyAddr);
    }

    // =========================================================================
    // Fuzz tests
    // =========================================================================

    function testFuzz_hashAuthorization_deterministicForSameInputs(
        uint256 chainId,
        uint256 nonce
    ) public {
        address logic = address(simpleLogic);
        bytes32 hashA = Auth7702.hashAuthorization(chainId, logic, nonce);
        bytes32 hashB = Auth7702.hashAuthorization(chainId, logic, nonce);
        assertEq(hashA, hashB);
    }

    function testFuzz_delegate_isDelegatedTo_alwaysTrue(uint256 pk) public {
        vm.assume(pk > 0 && pk < 115792089237316195423570985008687907852837564279074904382605163141518161494337);
        address eoa = delegate(pk, address(simpleLogic));
        assertTrue(isDelegatedTo(eoa, address(simpleLogic)));
    }

    function testFuzz_signAuthorization_recoversCorrectSigner(uint256 pk) public {
        vm.assume(pk > 0 && pk < 115792089237316195423570985008687907852837564279074904382605163141518161494337);
        address signer = vm.addr(pk);
        Auth7702.SignedAuthorization memory signed = signAuthorization(pk, address(simpleLogic), 0);
        bytes32 hash = Auth7702.hashAuthorization(signed.auth);
        address recovered = ecrecover(hash, signed.v, signed.r, signed.s);
        assertEq(recovered, signer);
    }
}