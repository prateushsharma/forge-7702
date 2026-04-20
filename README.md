# forge-7702

A Foundry testing library for EIP-7702.

> **"A developer who has never touched EIP-7702 should be able to write a complete test in under 5 minutes."**

EIP-7702 (included in the Ethereum Pectra hard fork) lets a regular EOA temporarily behave like a smart contract by delegating to a logic contract. Testing this in Foundry requires building authorization tuples, signing them correctly, and simulating delegation — forge-7702 wraps all of that into clean one-line helpers.

---

## Installation

```bash
forge install prateushsharma/forge-7702
```

Add to your `foundry.toml`:

```toml
remappings = ["forge-7702/=lib/forge-7702/src/"]
```

---

## Quick Start

```solidity
import {Test} from "forge-std/Test.sol";
import {EIP7702Helper} from "forge-7702/EIP7702Helper.sol";

contract MyWalletTest is Test, EIP7702Helper {
    uint256 ownerPk = uint256(keccak256("owner"));

    function test_delegation_works() public {
        address eoa = delegate(ownerPk, address(myLogicContract));
        assertTrue(isDelegatedTo(eoa, address(myLogicContract)));
    }
}
```

That's it. One import, one line.

---

## How It Works

### EIP-7702 in 30 seconds

EIP-7702 introduces a new transaction type (type-4) that lets an EOA set its code to a **delegation pointer**:

```
0xef0100 ++ address(logicContract)   // 23 bytes
```

Any call to the EOA is then forwarded to `logicContract`, executing in the EOA's own storage context. The EOA's private key still controls it — delegation can be revoked or changed at any time.

### How forge-7702 simulates this in Foundry

On mainnet, delegation is set by the EVM when processing a type-4 transaction. In Foundry tests we can't submit real type-4 transactions, so we use `vm.etch` — a Foundry cheat code that sets bytecode on any address:

```solidity
function delegate(uint256 pk, address logic) internal returns (address eoa) {
    eoa = vm.addr(pk);
    bytes memory ptr = abi.encodePacked(hex"ef0100", logic);
    vm.etch(eoa, ptr);
}
```

This correctly mimics the EVM — the EOA's code becomes the 23-byte delegation pointer, exactly as EIP-7702 specifies.

### Signing scheme

EIP-7702 uses a custom signing scheme — different from EIP-712 and standard transaction signing:

```
hash = keccak256(0x05 ++ rlp([chainId, address, nonce]))
```

`Auth7702.sol` implements this correctly so you never have to think about it.

---

## Library Structure

```
forge-7702/
├── src/
│   ├── Auth7702.sol              ← structs + EIP-7702 signing hash
│   ├── EIP7702Helper.sol         ← core helpers, inherit in your tests
│   ├── MockDelegatedAccount.sol  ← mock EOA, no private key needed
│   └── SessionKeyHelper.sol      ← session key helpers
└── test/
    └── EIP7702Helper.t.sol       ← library test suite
```

### Inheritance chain

```
forge-std/Test
    └── EIP7702Helper
            └── SessionKeyHelper
                    └── YourTest
```

---

## API Reference

### `Auth7702.sol`

Foundation library. Contains structs and the EIP-7702 signing hash. All other files import from here.

#### Structs

```solidity
struct Authorization {
    uint256 chainId;       // Chain this auth is valid on. 0 = any chain.
    address logicContract; // Contract the EOA delegates to.
    uint256 nonce;         // EOA nonce at signing time. Prevents replay.
}

struct SignedAuthorization {
    Authorization auth;
    uint8  v;
    bytes32 r;
    bytes32 s;
}
```

#### Constants

```solidity
uint8 internal constant MAGIC = 0x05; // EIP-7702 domain prefix
```

#### Functions

```solidity
// Hash an Authorization struct for signing
function hashAuthorization(Authorization memory auth) internal pure returns (bytes32);

// Convenience overload — hash directly from components
function hashAuthorization(uint256 chainId, address logicContract, uint256 nonce)
    internal pure returns (bytes32);
```

---

### `EIP7702Helper.sol`

Core helper. Inherit this in your test contracts.

#### Delegation

```solidity
// Delegate an EOA to a logic contract. Returns the EOA address.
function delegate(uint256 pk, address logic) internal returns (address eoa);

// Revoke delegation — clears the EOA's code.
function revoke(uint256 pk) internal;

// Re-delegate to a new logic contract in one call.
function redelegate(uint256 pk, address newLogic) internal returns (address eoa);
```

#### Inspection

```solidity
// Returns true if the EOA is delegated to the given logic contract.
function isDelegatedTo(address eoa, address logic) internal view returns (bool);

// Returns true if the EOA has any active delegation.
function isDelegated(address eoa) internal view returns (bool);

// Returns the logic contract the EOA is currently delegated to. Returns address(0) if none.
function getDelegatedLogic(address eoa) internal view returns (address);
```

#### Signing

```solidity
// Sign an EIP-7702 authorization. Uses block.chainid automatically.
function signAuthorization(uint256 pk, address logic, uint256 nonce)
    internal view returns (Auth7702.SignedAuthorization memory);

// Sign with an explicit chainId.
function signAuthorization(uint256 pk, address logic, uint256 nonce, uint256 chainId)
    internal pure returns (Auth7702.SignedAuthorization memory);
```

#### Execution

```solidity
// Execute a call as the EOA (via vm.prank). EOA must be delegated first.
function executeAs(uint256 pk, address target, bytes memory data)
    internal returns (bytes memory);

// Same but with ETH value.
function executeAs(uint256 pk, address target, bytes memory data, uint256 value)
    internal returns (bytes memory);
```

---

### `MockDelegatedAccount.sol`

A drop-in mock EOA for tests that don't need real private keys. Useful for quick unit tests where you just need a delegated account to exist.

#### Constructor

```solidity
// pk — deterministic private key to derive the mock EOA address from.
// Suggestion: uint256(keccak256("mock.eoa"))
constructor(uint256 pk);
```

#### State

```solidity
address public immutable eoa; // The mock EOA address
```

#### Functions

```solidity
// Simulate delegation — no signing required.
function simulateDelegate(address logic) external;

// Simulate revocation.
function simulateRevoke() external;

// Simulate re-delegation.
function simulateRedelegate(address newLogic) external;

// Execute a call as the mock EOA.
function executeAs(address target, bytes calldata data) external returns (bytes memory);
function executeAs(address target, bytes calldata data, uint256 value) external returns (bytes memory);

// Inspection — no eoa argument needed, the mock knows its own address.
function isDelegatedTo(address logic) external view returns (bool);
function isDelegated() external view returns (bool);
function getDelegatedLogic() external view returns (address);
```

#### Example

```solidity
MockDelegatedAccount mock = new MockDelegatedAccount(uint256(keccak256("mock.eoa")));
mock.simulateDelegate(address(myLogic));
mock.executeAs(address(myLogic), abi.encodeCall(IWallet.execute, (target, value, data)));
assertTrue(mock.isDelegatedTo(address(myLogic)));
```

---

### `SessionKeyHelper.sol`

High-level helpers for session key testing. Inherits `EIP7702Helper`.

#### Structs

```solidity
struct SessionConfig {
    address sessionKey;   // Address of the session key.
    address target;       // Only contract this key may call.
    bytes4  selector;     // Only function selector this key may call.
    address tokenIn;      // Input token (address(0) = ETH or N/A).
    address tokenOut;     // Output token (address(0) = N/A).
    uint256 maxAmount;    // Max token amount per execution.
    uint48  validAfter;   // Session start timestamp.
    uint48  validUntil;   // Session expiry timestamp.
    uint256 maxCalls;     // Max calls allowed. 0 = unlimited.
}

struct Call {
    address target;
    uint256 value;
    bytes   data;
}

struct ExecutionRequest {
    Call[]  calls;    // Batch of calls to execute.
    uint256 nonce;    // Session nonce — prevents replay.
    uint256 deadline; // Request expiry timestamp.
}

struct SignedExecutionRequest {
    ExecutionRequest req;
    uint8   v;
    bytes32 r;
    bytes32 s;
}
```

#### Session Config

```solidity
function buildSessionConfig(
    uint256 sessionKeyPk,
    address target,
    bytes4  selector,
    address tokenIn,
    address tokenOut,
    uint256 maxAmount,
    uint256 duration,   // seconds from now
    uint256 maxCalls
) internal view returns (SessionConfig memory);
```

#### Execution Requests

```solidity
// Single call request
function buildExecutionRequest(
    address target, uint256 value, bytes memory data,
    uint256 nonce, uint256 deadline
) internal pure returns (ExecutionRequest memory);

// Batch request
function buildBatchExecutionRequest(
    Call[] memory calls, uint256 nonce, uint256 deadline
) internal pure returns (ExecutionRequest memory);
```

#### Signing — Raw keccak256

```solidity
// Sign using raw keccak256. Simpler, no domain separator needed.
function signExecutionRequest(uint256 sessionKeyPk, ExecutionRequest memory req)
    internal pure returns (SignedExecutionRequest memory);
```

#### Signing — EIP-712

```solidity
// Build a domain separator for a verifying contract.
function buildDomainSeparator(string memory name, string memory version, address verifier)
    internal view returns (bytes32);

// Sign using EIP-712 typed structured data.
function signExecutionRequest712(
    uint256 sessionKeyPk, ExecutionRequest memory req, bytes32 domainSeparator
) internal pure returns (SignedExecutionRequest memory);
```

#### Validation & Recovery

```solidity
// Returns true if the session is currently active (within time window).
function isSessionActive(SessionConfig memory config) internal view returns (bool);

// Returns true if the execution request has not expired.
function isRequestValid(ExecutionRequest memory req) internal view returns (bool);

// Recover signer from a raw-signed request.
function recoverSigner(SignedExecutionRequest memory signed) internal pure returns (address);

// Recover signer from an EIP-712 signed request.
function recoverSigner712(SignedExecutionRequest memory signed, bytes32 domainSeparator)
    internal pure returns (address);
```

---

## Full Example — Delegation + Execution

```solidity
import {Test} from "forge-std/Test.sol";
import {EIP7702Helper} from "forge-7702/EIP7702Helper.sol";

contract MyLogic {
    uint256 public value;
    function setValue(uint256 v) external { value = v; }
}

contract DelegationTest is Test, EIP7702Helper {
    uint256 ownerPk = uint256(keccak256("owner"));
    MyLogic logic;

    function setUp() public {
        logic = new MyLogic();
    }

    function test_delegate_execute_revoke() public {
        // 1. Delegate
        address eoa = delegate(ownerPk, address(logic));
        assertTrue(isDelegatedTo(eoa, address(logic)));

        // 2. Execute as EOA
        executeAs(ownerPk, address(logic), abi.encodeCall(MyLogic.setValue, (42)));
        assertEq(logic.value(), 42);

        // 3. Revoke
        revoke(ownerPk);
        assertFalse(isDelegated(eoa));
    }
}
```

---

## Full Example — Session Keys

```solidity
import {Test} from "forge-std/Test.sol";
import {SessionKeyHelper} from "forge-7702/SessionKeyHelper.sol";

contract SwapLogic {
    function swap(uint256 amount) external {}
}

contract SessionKeyTest is Test, SessionKeyHelper {
    uint256 ownerPk      = uint256(keccak256("owner"));
    uint256 sessionKeyPk = uint256(keccak256("sessionKey"));
    SwapLogic logic;

    function setUp() public {
        logic = new SwapLogic();
        delegate(ownerPk, address(logic));
    }

    function test_session_key_signs_and_recovers() public {
        // 1. Build session config
        SessionConfig memory config = buildSessionConfig(
            sessionKeyPk,
            address(logic),
            SwapLogic.swap.selector,
            address(0), address(0),
            1000e18,
            1 days,
            10
        );
        assertTrue(isSessionActive(config));

        // 2. Build and sign an execution request
        ExecutionRequest memory req = buildExecutionRequest(
            address(logic),
            0,
            abi.encodeCall(SwapLogic.swap, (500e18)),
            0,
            block.timestamp + 1 hours
        );
        SignedExecutionRequest memory signed = signExecutionRequest(sessionKeyPk, req);

        // 3. Verify signer
        assertEq(recoverSigner(signed), vm.addr(sessionKeyPk));
    }
}
```

---

## Running the Tests

```bash
forge test -vv
```

Run with gas reporting:

```bash
forge test -vv --gas-report
```

Run a specific test:

```bash
forge test --match-test test_delegate_execute_revoke -vvv
```

---

## Glossary

| Term | Meaning |
|------|---------|
| EOA | Externally Owned Account — a regular wallet with a private key, no code |
| Logic Contract | The smart contract the EOA delegates execution to |
| Delegation Pointer | `0xef0100 ++ address` — 23 bytes set as the EOA's code by EIP-7702 |
| Authorization Tuple | `{ chainId, logicContract, nonce }` — signed by the EOA owner |
| Type-4 Transaction | New Ethereum tx type introduced by EIP-7702, contains an auth list |
| Session Key | A secondary key with scoped permissions to act on behalf of the EOA |
| `vm.etch` | Foundry cheat code — sets bytecode of any address in the test environment |
| `forge-std` | Foundry's standard library — forge-7702 builds on top of it |
| `SignedAuthorization` | Authorization struct + `{ v, r, s }` ECDSA signature |
| MAGIC | `0x05` — EIP-7702 domain prefix prepended before RLP payload when hashing |

---

## License

MIT
------
Made with  🩷 by Prateush Sharma
