import nacl from "tweetnacl";
import * as Crypto from "expo-crypto";
import { fromByteArray, toByteArray } from "base64-js";

nacl.setPRNG((target, length) => target.set(Crypto.getRandomBytes(length)));
const enc = new TextEncoder();
const dec = new TextDecoder();

export type Identity = {
  boxPublicKey: string;
  boxSecretKey: string;
  signingPublicKey: string;
  signingSecretKey: string;
};

export type EncryptedEnvelope = {
  id: string;
  recipient: string;
  ephemeralPublicKey: string;
  nonce: string;
  ciphertext: string;
  signature: string;
};

export type IncomingEnvelope = EncryptedEnvelope & {
  sender: string;
  senderSigningPublicKey: string;
  createdAt: number;
};

export function generateIdentity(): Identity {
  const box = nacl.box.keyPair();
  const signing = nacl.sign.keyPair();
  return {
    boxPublicKey: fromByteArray(box.publicKey),
    boxSecretKey: fromByteArray(box.secretKey),
    signingPublicKey: fromByteArray(signing.publicKey),
    signingSecretKey: fromByteArray(signing.secretKey),
  };
}

function signedBytes(message: Pick<EncryptedEnvelope, "id"|"recipient"|"ephemeralPublicKey"|"nonce"|"ciphertext">) {
  return enc.encode(JSON.stringify([
    message.id, message.recipient, message.ephemeralPublicKey,
    message.nonce, message.ciphertext
  ]));
}

export function encryptMessage(
  plaintext: string,
  recipient: string,
  recipientBoxPublicKey: string,
  identity: Identity
): EncryptedEnvelope {
  if (!plaintext.trim()) throw new Error("Escribe un mensaje.");
  const ephemeral = nacl.box.keyPair();
  const nonce = Crypto.getRandomBytes(nacl.box.nonceLength);
  const messageId = Crypto.randomUUID();
  const cipher = nacl.box(
    enc.encode(plaintext),
    nonce,
    toByteArray(recipientBoxPublicKey),
    ephemeral.secretKey
  );
  const envelope: EncryptedEnvelope = {
    id: messageId,
    recipient,
    ephemeralPublicKey: fromByteArray(ephemeral.publicKey),
    nonce: fromByteArray(nonce),
    ciphertext: fromByteArray(cipher),
    signature: "",
  };
  envelope.signature = fromByteArray(
    nacl.sign.detached(signedBytes(envelope), toByteArray(identity.signingSecretKey))
  );
  ephemeral.secretKey.fill(0);
  return envelope;
}

export function decryptMessage(
  envelope: IncomingEnvelope,
  ownUsername: string,
  identity: Identity
): string {
  const valid = nacl.sign.detached.verify(
    signedBytes(envelope),
    toByteArray(envelope.signature),
    toByteArray(envelope.senderSigningPublicKey)
  );
  if (!valid) throw new Error("Firma del remitente inválida.");
  if (envelope.recipient.toLowerCase() !== ownUsername.toLowerCase()) {
    throw new Error("El mensaje no corresponde a esta cuenta.");
  }
  const plain = nacl.box.open(
    toByteArray(envelope.ciphertext),
    toByteArray(envelope.nonce),
    toByteArray(envelope.ephemeralPublicKey),
    toByteArray(identity.boxSecretKey)
  );
  if (!plain) throw new Error("No se pudo autenticar o descifrar el mensaje.");
  return dec.decode(plain);
}

export async function fingerprint(boxPublicKey: string, signingPublicKey: string) {
  const digest = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    boxPublicKey + "." + signingPublicKey
  );
  return digest.slice(0, 40).toUpperCase().match(/.{1,4}/g)?.join(" ") ?? digest;
}

export function newAuthToken() {
  return fromByteArray(Crypto.getRandomBytes(32));
}
