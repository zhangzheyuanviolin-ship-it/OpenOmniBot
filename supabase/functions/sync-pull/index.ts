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
    const cursor = Number(body.cursor ?? 0)
    const limit = Math.min(Math.max(Number(body.limit ?? 200), 1), 500)
    if (!namespace || !deviceId) {
      return jsonResponse({ error: 'namespace and deviceId are required' }, { status: 400 })
    }
    const namespaceRow = await ensureNamespace(client, namespace)
    const verified = await verifySignedRequest(request, rawBody, namespaceRow.syncSecret)
    await consumeNonce(client, verified.namespace, verified.deviceId, verified.nonce)
    await upsertDevice(client, namespace, deviceId)

    const changesQuery = await client
      .from('sync_change_log')
      .select('cursor, doc_type, doc_sync_id, op_id, op_type, content_hash, device_id, body')
      .eq('namespace', namespace)
      .gt('cursor', cursor)
      .neq('device_id', deviceId)
      .order('cursor', { ascending: true })
      .limit(limit)
    if (changesQuery.error) {
      throw changesQuery.error
    }
    const changes = (changesQuery.data ?? []).map((item) => ({
      cursor: item.cursor,
      docType: item.doc_type,
      docSyncId: item.doc_sync_id,
      opId: item.op_id,
      opType: item.op_type,
      contentHash: item.content_hash,
      deviceId: item.device_id,
      payload: item.body ?? {},
    }))
    const nextCursor = changes.length > 0
      ? changes[changes.length - 1].cursor
      : cursor
    return jsonResponse({
      nextCursor,
      changes,
    })
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      { status: 400 },
    )
  }
})
