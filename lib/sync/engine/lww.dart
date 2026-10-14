// Last-writer-wins per record ("conflicts"): what counts is updatedAt from
// the record itself (not created_at of the event); on a tie the device ID
// decides lexicographically. Equal values = the same state (e.g. our own
// echo from the relay) → do nothing.

/// true if the remote state should replace the local one.
bool remoteWins({
  required int remoteUpdatedAt,
  required String remoteDeviceId,
  required int localUpdatedAt,
  required String? localDeviceId,
}) {
  if (remoteUpdatedAt != localUpdatedAt) {
    return remoteUpdatedAt > localUpdatedAt;
  }
  return remoteDeviceId.compareTo(localDeviceId ?? '') > 0;
}
