/** Modern target SDK; location is needed for Wi-Fi Aware through Android 12L. */
export function meshPermissions(api: number, wifiAware = true): string[] {
  const permissions: string[] = [];
  if (api >= 31) permissions.push(
    'android.permission.BLUETOOTH_SCAN',
    'android.permission.BLUETOOTH_CONNECT',
    'android.permission.BLUETOOTH_ADVERTISE',
  );
  if (api >= 33 && wifiAware) permissions.push('android.permission.NEARBY_WIFI_DEVICES');
  if (api >= 23 && (api <= 30 || (api <= 32 && wifiAware))) permissions.push(
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_FINE_LOCATION',
  );
  return permissions;
}
