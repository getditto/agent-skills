import { PermissionsAndroid, Platform, type Permission } from 'react-native';
import { meshPermissions } from './android-permissions';

export async function requestMeshPermissions() {
  if (Platform.OS !== 'android') return { granted: true, blocked: false };
  const requested = meshPermissions(Number(Platform.Version)) as Permission[];
  const results = await PermissionsAndroid.requestMultiple(requested);
  return {
    granted: requested.every((permission) => results[permission] === PermissionsAndroid.RESULTS.GRANTED),
    blocked: requested.some((permission) => results[permission] === PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN),
  };
}
