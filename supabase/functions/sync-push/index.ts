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
    const operations = Array.isArray(body.operations) ? body.operations : []
    if (!namespace || !deviceId) {
      return jsonResponse({ error: 'namespace and deviceId are required' }, { status: 400 })
    }
    const namespaceRow = await ensureNamespace(client, namespace)
    const verified = await verifySignedRequest(request, rawBody, namespaceRow.syncSecret)
    await consumeNonce(client, verified.namespace, verified.deviceId, verified.nonce)
    await upsertDevice(client, namespace, deviceId)

    const acknowledgedOpIds: string[] = []
    for (const operation of operations) {
      const opId = operation?.opId?.toString().trim() ?? ''
      const docType = operation?.docType?.toString().trim() ?? ''
      const docSyncId = operation?.docSyncId?.toString().trim() ?? ''
      const opType = operation?.opType?.toString().trim() ?? ''
      const contentHash = operation?.contentHash?.toString().trim() ?? ''
      const payload = operation?.payload ?? {}
      if (!opId || !docType || !docSyncId || !opType) {
        continue
      }

      const existing = await client
        .from('sync_change_log')
        .select('op_id')
        .eq('op_id', opId)
        .maybeSingle()
      if (existing.error) {
        throw existing.error
      }
      if (existing.data) {
        acknowledgedOpIds.push(opId)
        continue
      }

      if (docType === 'file') {
        const relativePath = payload.relativePath?.toString() ?? docSyncId
        const response = await client
          .from('sync_files')
          .upsert(
            {
              namespace,
              relative_path: relativePath,
              content_hash: contentHash,
              object_key: payload.objectKey?.toString() ?? '',
              size_bytes: Number(payload.sizeBytes ?? 0),
              last_modified_at: Number(payload.lastModifiedAt ?? 0),
              deleted: opType === 'delete' || payload.deleted === true,
              updated_by_device: deviceId,
              updated_at: new Date().toISOString(),
            },
            { onConflict: 'namespace,relative_path' },
          )
        if (response.error) {
          throw response.error
        }
      } else {
        const response = await client
          .from('sync_documents')
          .upsert(
            {
              namespace,
              doc_type: docType,
              doc_sync_id: docSyncId,
              content_hash: contentHash,
              deleted: opType === 'delete' || payload.deleted === true,
              payload,
              updated_by_device: deviceId,
              updated_at: new Date().toISOString(),
            },
            { onConflict: 'namespace,doc_type,doc_sync_id' },
          )
        if (response.error) {
          throw response.error
        }
      }

      const inserted = await client
        .from('sync_change_log')
        .insert({
          namespace,
          doc_type: docType,
          doc_sync_id: docSyncId,
          op_id: opId,
          op_type: opType,
          content_hash: contentHash,
          device_id: deviceId,
          body: payload,
        })
      if (inserted.error) {
        throw inserted.error
      }
      acknowledgedOpIds.push(opId)
    }

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
      acknowledgedOpIds,
      cursor: latestCursor.data?.cursor ?? 0,
    })
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : 'Unknown error' },
      { status: 400 },
    )
  }
})
