# Security policy

## Reporting a vulnerability
Please do not open a public issue. Report it privately, either:
- through GitHub: **Security**, then **Report a vulnerability** on the [VerbNest repository](https://github.com/Omni-Technical-Solutions/VerbNest/security/advisories/new); or
- by email to **info@omnits.pro** with "VerbNest security" in the subject.

Include the version (Settings, or the release you installed), your platform, what you found, and the steps to reproduce it. A proof of concept helps. Do not include real credentials or other people's data.

You can expect an acknowledgement within 5 working days and a first assessment within 10. We will keep you informed, agree a date for disclosure with you, and credit you in the release notes if you want.

## Supported versions
Only the latest release receives security fixes.

## What is in scope
VerbNest sends only the requests you write, keeps workspaces on your device, and stores secret variables in the system keychain or a local vault. Reports about these are in scope: leaking secrets (into history, logs, exports, scripts or the network), script sandbox escapes, certificate-validation bypasses, and unsafe handling of imported files (Postman, OpenAPI, HAR, cURL, workspace files).

Out of scope: behaviour of the servers you test, findings that need a rooted or jailbroken device or physical access to an unlocked device, and denial of service by opening a very large file.
