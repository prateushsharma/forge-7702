# Changelog

All notable changes to forge-7702 will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-04-20

### Added
- `Auth7702.sol` — Authorization structs, EIP-7702 signing hash, internal RLP encoding
- `EIP7702Helper.sol` — Core test helper: delegate, revoke, redelegate, signAuthorization, executeAs
- `MockDelegatedAccount.sol` — Keyless mock EOA for quick unit test setup
- `SessionKeyHelper.sol` — Session config builder, raw + EIP-712 execution request signing, batch support
- Full test suite with fuzz tests
- GitHub Actions CI (test on push/PR, publish on tag)
- NPM + GitHub Packages publishing