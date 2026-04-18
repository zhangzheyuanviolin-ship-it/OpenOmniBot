import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8'

type AdminClient = ReturnType<typeof createClient>

const jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
}

export function getAdminClient() {
  const url = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !serviceRoleKey) {
    throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY')
  }
  return createClient(url, serviceRoleKey)
}

export function jsonResponse(payload: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(payload), {
    ...init,
    headers: {
      ...jsonHeaders,
      ...(init.headers ?? {}),
    },
  })
}

export async function readJsonRequest(request: Request) {
  const rawBody = await request.text()
  const body = rawBody ? JSON.parse(rawBody) : {}
  return { rawBody, body }
}

export async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  )
  return Array.from(new Uint8Array(digest))
    .map((item) => item.toString(16).padStart(2, '0'))
    .join('')
}

export async function hmacSha256Hex(secret: string, content: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(content),
  )
  return Array.from(new Uint8Array(signature))
    .map((item) => item.toString(16).padStart(2, '0'))
    .join('')
}

export async function verifySignedRequest(
  request: Request,
  rawBody: string,
  secret: string,
) {
  const namespace = request.headers.get('x-sync-namespace')?.trim() ?? ''
  const deviceId = request.headers.get('x-sync-device-id')?.trim() ?? ''
  const timestamp = request.headers.get('x-sync-timestamp')?.trim() ?? ''
  const nonce = request.headers.get('x-sync-nonce')?.trim() ?? ''
  const bodyHash = request.headers.get('x-sync-body-hash')?.trim() ?? ''
  const signature = request.headers.get('x-sync-signature')?.trim() ?? ''
  if (!namespace || !deviceId || !timestamp || !nonce || !bodyHash || !signature) {
    throw new Error('Missing sync signature headers')
  }
  const now = Date.now()
  const ts = Number(timestamp)
  if (!Number.isFinite(ts) || Math.abs(now - ts) > 5 * 60 * 1000) {
    throw new Error('Expired sync request timestamp')
  }
  const actualBodyHash = await sha256Hex(rawBody)
  if (actualBodyHash !== bodyHash) {
    throw new Error('Body hash mismatch')
  }
  const signingText = [
    request.method.toUpperCase(),
    new URL(request.url).pathname,
    timestamp,
    nonce,
    bodyHash,
  ].join('\n')
  const expected = await hmacSha256Hex(secret, signingText)
  if (expected !== signature) {
    throw new Error('Invalid sync signature')
  }
  return { namespace, deviceId, nonce }
}

export async function ensureNamespace(
  client: AdminClient,
  namespace: string,
  providedSecret?: string,
) {
  const query = await client
    .from('sync_namespaces')
    .select('namespace, sync_secret')
    .eq('namespace', namespace)
    .maybeSingle()

  if (query.error) {
    throw query.error
  }
  if (query.data) {
    return { namespace, syncSecret: query.data.sync_secret, created: false }
  }
  if (!providedSecret) {
    throw new Error('Namespace not found; syncSecret is required for bootstrap')
  }
  const inserted = await client
    .from('sync_namespaces')
    .insert({
      namespace,
      sync_secret: providedSecret,
    })
    .select('namespace, sync_secret')
    .single()
  if (inserted.error) {
    throw inserted.error
  }
  return {
    namespace,
    syncSecret: inserted.data.sync_secret,
    created: true,
  }
}

export async function consumeNonce(
  client: AdminClient,
  namespace: string,
  deviceId: string,
  nonce: string,
) {
  const inserted = await client
    .from('sync_request_nonces')
    .insert({
      namespace,
      device_id: deviceId,
      nonce,
    })
  if (inserted.error) {
    if (inserted.error.code === '23505') {
      throw new Error('Duplicate sync nonce')
    }
    throw inserted.error
  }
}

export async function upsertDevice(
  client: AdminClient,
  namespace: string,
  deviceId: string,
) {
  const response = await client
    .from('sync_devices')
    .upsert(
      {
        namespace,
        device_id: deviceId,
        updated_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
      },
      { onConflict: 'namespace,device_id' },
    )
  if (response.error) {
    throw response.error
  }
}
