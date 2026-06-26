import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEY = 'stereoConfig';

const DEFAULT_CONFIG = {
  name: 'Harman Kardon',
  ip: '',
  port: 10025,
  deviceType: 'avr',
  zone: 'Main Zone',
};

export async function loadStereoConfig() {
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  if (!raw) {
    return DEFAULT_CONFIG;
  }
  return { ...DEFAULT_CONFIG, ...JSON.parse(raw) };
}

export async function saveStereoConfig(config) {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(config));
}
