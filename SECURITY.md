# Security Policy

## Supported Versions

Security fixes are provided for the latest published CBSS developer-preview
release. Older 0.x releases may be superseded instead of patched independently.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability.

Use the repository's private GitHub security-advisory reporting flow. Include:

- The affected version or commit
- Platform and runtime-link setup
- A minimal reproduction
- Expected and observed behavior
- Potential impact

Do not include production credentials, private data, or third-party secrets.

The maintainers will acknowledge a complete report, reproduce it privately,
and coordinate disclosure after a fix is available. Native library loading,
FFI ownership, image/font parsing, clipboard access, and event injection should
be treated as security-sensitive areas.
