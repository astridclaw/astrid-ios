# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### How to Report

**DO NOT** open a public GitHub issue for security vulnerabilities.

Instead, please email security concerns to: **security@astrid.cc**

Include the following information:
- Type of vulnerability (e.g., XSS, SQL injection, authentication bypass)
- Steps to reproduce the issue
- Potential impact
- Any suggested fixes (optional)

### What to Expect

1. **Acknowledgment**: We will acknowledge receipt within 48 hours
2. **Initial Assessment**: We will provide an initial assessment within 7 days
3. **Resolution Timeline**: We aim to resolve critical issues within 30 days
4. **Disclosure**: We will coordinate disclosure timing with you

### Scope

The following are in scope for security reports:
- Authentication and authorization vulnerabilities
- Data exposure or leakage
- Cross-site scripting (XSS)
- SQL injection or other injection attacks
- Server-side request forgery (SSRF)
- Remote code execution
- Privilege escalation

### Out of Scope

- Denial of service attacks
- Social engineering attacks
- Physical security issues
- Issues in third-party dependencies (report to the dependency maintainer)
- Issues requiring physical access to a user's device

## Security Best Practices

When contributing to Astrid, please follow these security guidelines:

### Authentication & Authorization
- Always verify user sessions before processing sensitive requests
- Use the existing authentication middleware
- Never trust client-side data for authorization decisions

### Data Handling
- Sanitize all user input
- Use Core Data predicates safely (avoid string interpolation)
- Never log sensitive data (passwords, tokens, API keys)
- Store credentials in Keychain, not UserDefaults

### API Security
- Validate all input parameters
- Implement rate limiting on sensitive endpoints
- Use appropriate HTTP status codes for errors

### Dependencies
- Keep Xcode and iOS SDK updated
- Review Apple security advisories regularly
- Avoid third-party dependencies when possible (system frameworks preferred)

## Recognition

We appreciate security researchers who help keep Astrid secure. With your permission, we will acknowledge your contribution in our release notes.

## Updates

This security policy may be updated from time to time. Please check back regularly for any changes.
