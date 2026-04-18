import {
  consumeNonce,
  ensureNamespace,
  getAdminClient,
  jsonResponse,
  readJsonRequest,
  upsertDevice,
  verifySignedRequest,
} from '../_shared/sync.ts'

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, { status: 405 })
  }
  try {
    const client = getAdminClient()
    const { rawBody, body } = await readJsonRequest(request)
    const namespace = body.namespace?.toString().trim() ?? ''
    const deviceId = body.deviceId?.toString().trim() ?? ''
    const providedSecret = body.syncSecret?.toString().trim() ?? ''
    if (!namespace || !deviceId) {
      return jsonResponse({ error: 'namespace and deviceId are required' }, { status: 400 })
    }
    const namespaceRow = await ensureNamespace(client, namespace, providedSecret)
    const verified = await verifySignedRequest(request, rawBody, namespaceRow.syncSecret)
    await consumeNonce(client, verified.namespace, verified.deviceId, verified.nonce)
    await upsertDevice(client, namespace, deviceId)
    const latestCursor = await client
      .from('sync_change_log')
      .select('cursor')
      .eq('namespace', namespace)
      .order('cursor', { ascending: false })
      .limit(1)
      .maybeSingle()
    if (latestCursor.error) {
      throw latestCursor.error
    }
    return jsonResponse({
      namespace,
      registered: namespaceRow.created,
      remoteCursor: latestCursor.data?.cursor ?? 0,
    })
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      { status: 400 },
    )
  }
})
