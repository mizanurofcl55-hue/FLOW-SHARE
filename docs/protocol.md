# FlowShare protocol v1

Transport: native TCP with TLS >= 1.2 (prefer the strongest mutually supported version). IPv4 private, loopback or link-local endpoints only in the app. No DNS hostnames, public internet destinations, relay, or plaintext fallback. The core validates IPv6 local literals, but the current advertisement/listener UI uses IPv4.

## Identity and approval

Each installation creates a 2048-bit RSA identity and self-signed X.509 certificate. Private material is stored by the app in the OS secure store. A pairing invitation contains protocol version, numeric address, port, display name, platform and SHA-256 DER certificate pin, encoded as `flowshare://pair/<base64url JSON>`.

1. Sender establishes TLS, allowing only the exact advertised certificate pin, then explicitly checks pin and validity again after handshake.
2. Receiver sends a fresh 192-bit nonce and protocol version.
3. Sender signs the UTF-8 canonical JSON array `["FlowShare/v1/auth", nonce, receiverCertificatePin, senderPublicKeyFingerprint, manifestDigest, senderName]` using RSA/SHA-256.
4. Receiver validates the signature and bounded metadata. Both display the first 128 bits of SHA-256 of that transcript as **four groups of eight hex digits**.
5. Both users compare every group and explicitly approve. Sender sends `confirmed`; receiver sends `ready` only after its approval, storage checks and recovery validation.

Names and mDNS advertisements are not authentication. A compromised invitation can be detected only if users correctly compare the displayed code on their intended devices. Remembered identities never auto-accept a transfer in this preview. No claim of independent cryptographic audit is made.

## Framing

Every frame has a four-byte unsigned big-endian length, including its one-byte kind. Kind 1 is a UTF-8 JSON object, limited to 64 KiB excluding kind. Kind 2 has file index (uint32), offset (uint64), and up to 1 MiB of bytes, all after the kind byte. Frame sizes are checked before allocating the body. Readers retain at most the current frame and socket chunk.

Manifest: random 32-character transfer ID, 1–128 files, each with a safe basename, exact nonnegative size and lowercase SHA-256. Total is bounded to 1 TiB. Source files are hashed before offer and rechecked before connection/retry. Index and sequential offset must exactly match the expected position.

Each data chunk gets an ACK with file index and next offset. The sender sends `fileEnd`; the receiver flushes and closes the temporary file, computes SHA-256, checks the target does not exist, renames into its private destination, then responds `committed`. Empty files follow the same verification path without data chunks.

After all files, sender sends `finish`. Only a receiver `complete` response permits sender success. A network failure between receiver commit and final acknowledgement can yield receiver success and sender failure; retry safely revalidates already committed files.

## Recovery and limits

The journal binds sender public-key fingerprint and manifest digest. Completed files are rehashed before being offered in `ready.completed`. Partial chunks are not trusted or resumed. An interrupted file restarts at byte zero. A changed source or inconsistent journal fails closed.

One incoming session is admitted at a time, with a global five-attempts/minute limit before TLS promotion and a 15-second TLS timeout. Approval expires after 50–55 seconds. Socket frame reads time out after 60 seconds of inactivity. Very slow disks or huge verification operations can time out; this is a documented preview limitation. Cancellation closes the socket and removes the current `.part` file when the process is alive.
