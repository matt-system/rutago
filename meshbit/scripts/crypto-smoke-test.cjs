const assert = require("node:assert/strict");
const { randomFillSync } = require("node:crypto");
const nacl = require("tweetnacl");

nacl.setPRNG((target, length) => randomFillSync(target, 0, length));

const senderSigning = nacl.sign.keyPair();
const recipient = nacl.box.keyPair();
const ephemeral = nacl.box.keyPair();
const nonce = nacl.randomBytes(nacl.box.nonceLength);
const message = new TextEncoder().encode("Meshbit encrypted message test");
const encrypted = nacl.box(message, nonce, recipient.publicKey, ephemeral.secretKey);
const decrypted = nacl.box.open(encrypted, nonce, ephemeral.publicKey, recipient.secretKey);

assert.ok(decrypted, "recipient should decrypt the authenticated ciphertext");
assert.equal(new TextDecoder().decode(decrypted), "Meshbit encrypted message test");

const signedPayload = new TextEncoder().encode("message-id|recipient|nonce|ciphertext");
const signature = nacl.sign.detached(signedPayload, senderSigning.secretKey);
assert.equal(nacl.sign.detached.verify(signedPayload, signature, senderSigning.publicKey), true);

const tampered = signedPayload.slice();
tampered[0] ^= 1;
assert.equal(nacl.sign.detached.verify(tampered, signature, senderSigning.publicKey), false);

const wrongRecipient = nacl.box.keyPair();
assert.equal(nacl.box.open(encrypted, nonce, ephemeral.publicKey, wrongRecipient.secretKey), null);

console.log("Meshbit crypto primitive smoke test passed (box encryption, signature and tamper rejection).");
