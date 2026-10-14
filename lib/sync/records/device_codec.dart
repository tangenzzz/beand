// Device presence: one record per device, "I'm here, last seen at …".
// ID = device ID. Older app versions don't know the type and skip it.

const deviceType = 'device';

Map<String, Object?> deviceToSyncData(int lastSeen) => {'lastSeen': lastSeen};
