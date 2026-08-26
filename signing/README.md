# Release signing

`luqma-release.jks` — generated 2026-08-26, valid for ~27 years. **This folder is
gitignored on purpose**: the `.jks` is the identity of every Luqma app on the Play
Store, and `key.properties` holds its passwords.

- **Back both files up** (password manager, then a second place) before trusting this
  machine with anything. A lost keystore cannot be regenerated against a published app;
  Google's key reset is slow, manual, and only works if Play App Signing was enrolled.
- `key.properties` paths are relative to each app's `android/app/`, hence the
  `../../../signing/`.
- The upload key's fingerprints, for OAuth client registration and the Play Console:

```
SHA-1:   8E:57:88:E6:3C:E9:A7:EB:CE:5F:DB:49:4F:A8:4C:22:E1:BC:12:24
SHA-256: see `keytool -list -v -keystore luqma-release.jks -alias luqma`
```

Register that SHA-1 against each application id (`com.luqma.customer`,
`com.luqma.merchant`, `com.luqma.admin`) wherever Google Sign-In clients are configured.
