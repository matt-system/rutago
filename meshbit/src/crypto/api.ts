import type { EncryptedEnvelope, IncomingEnvelope } from "./e2ee";

const API = "https://meshbit.matthieupierremarie.workers.dev";

async function call<T>(path: string, token?: string, body?: unknown): Promise<T> {
  const response = await fetch(API + path, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: "Bearer " + token } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error || "Error de conexión (" + response.status + ").");
  return data as T;
}

export type PublicKeys = {
  username: string;
  boxPublicKey: string;
  signingPublicKey: string;
};

export async function register(username: string, authToken: string, boxPublicKey: string, signingPublicKey: string) {
  return call<{id:string;username:string}>("/api/register", undefined, {
    username, authToken, boxPublicKey, signingPublicKey,
  });
}
export async function me(token: string) {
  return call<{id:string;username:string;boxPublicKey:string;signingPublicKey:string}>("/api/me", token);
}
export async function getKeys(token: string, username: string) {
  return call<PublicKeys>("/api/keys/" + encodeURIComponent(username), token);
}
export async function send(token: string, envelope: EncryptedEnvelope) {
  return call<{accepted:boolean;id:string}>("/api/messages", token, envelope);
}
export async function inbox(token: string) {
  return call<{messages:IncomingEnvelope[]}>("/api/inbox", token);
}
export async function acknowledge(token: string, ids: string[]) {
  return call<{acknowledged:number}>("/api/ack", token, {ids});
}
