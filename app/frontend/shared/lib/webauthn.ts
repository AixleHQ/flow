// Minimal WebAuthn helpers.
//
// Deliberately no @simplewebauthn/browser: the ceremony is two `navigator
// .credentials` calls plus base64url conversion, and adding a dependency to the
// shared node_modules for that is not worth it.

const toBase64Url = (buffer: ArrayBuffer): string =>
  btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

// Returns Uint8Array<ArrayBuffer>, not Uint8Array<ArrayBufferLike>: the WebAuthn
// types want a BufferSource backed by a real ArrayBuffer, and `Uint8Array.from`
// produces the looser type that a SharedArrayBuffer would also satisfy.
const fromBase64Url = (value: string): Uint8Array<ArrayBuffer> => {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
};

export function isSupported(): boolean {
  return typeof window !== 'undefined' && !!window.PublicKeyCredential;
}

/**
 * What the server sends: the same shape the browser wants, except that every
 * ArrayBuffer field is a base64url string, because JSON has no binary type.
 */
interface EncodedDescriptor {
  id: string;
  type: PublicKeyCredentialType;
  transports?: AuthenticatorTransport[];
}

interface EncodedCreationOptions extends Omit<
  PublicKeyCredentialCreationOptions,
  'challenge' | 'user' | 'excludeCredentials'
> {
  challenge: string;
  user: Omit<PublicKeyCredentialUserEntity, 'id'> & { id: string };
  excludeCredentials?: EncodedDescriptor[];
}

interface EncodedRequestOptions extends Omit<PublicKeyCredentialRequestOptions, 'challenge' | 'allowCredentials'> {
  challenge: string;
  allowCredentials?: EncodedDescriptor[];
}

const decodeDescriptor = (descriptor: EncodedDescriptor): PublicKeyCredentialDescriptor => ({
  ...descriptor,
  id: fromBase64Url(descriptor.id),
});

/** The browser rejects the whole ceremony if any of these stay base64url strings. */
function decodeCreationOptions(options: EncodedCreationOptions): PublicKeyCredentialCreationOptions {
  return {
    ...options,
    challenge: fromBase64Url(options.challenge),
    user: { ...options.user, id: fromBase64Url(options.user.id) },
    excludeCredentials: (options.excludeCredentials ?? []).map(decodeDescriptor),
  };
}

function decodeRequestOptions(options: EncodedRequestOptions): PublicKeyCredentialRequestOptions {
  return {
    ...options,
    challenge: fromBase64Url(options.challenge),
    allowCredentials: (options.allowCredentials ?? []).map(decodeDescriptor),
  };
}

export async function createCredential(options: EncodedCreationOptions) {
  const credential = (await navigator.credentials.create({
    publicKey: decodeCreationOptions(options),
  })) as PublicKeyCredential;
  const response = credential.response as AuthenticatorAttestationResponse;

  return {
    type: credential.type,
    id: credential.id,
    rawId: toBase64Url(credential.rawId),
    response: {
      clientDataJSON: toBase64Url(response.clientDataJSON),
      attestationObject: toBase64Url(response.attestationObject),
    },
  };
}

export async function getCredential(options: EncodedRequestOptions) {
  const credential = (await navigator.credentials.get({
    publicKey: decodeRequestOptions(options),
  })) as PublicKeyCredential;
  const response = credential.response as AuthenticatorAssertionResponse;

  return {
    type: credential.type,
    id: credential.id,
    rawId: toBase64Url(credential.rawId),
    response: {
      clientDataJSON: toBase64Url(response.clientDataJSON),
      authenticatorData: toBase64Url(response.authenticatorData),
      signature: toBase64Url(response.signature),
      userHandle: response.userHandle ? toBase64Url(response.userHandle) : null,
    },
  };
}
