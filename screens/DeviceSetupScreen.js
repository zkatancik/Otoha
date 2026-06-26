import React, { useEffect, useState } from 'react';
import { View, Text, TextInput, Button, StyleSheet, FlatList, Alert } from 'react-native';
import { loadStereoConfig, saveStereoConfig } from '../services/stereoConfig';
import { discoverStereos } from '../services/stereoDiscovery';

const DeviceSetupScreen = ({ navigation }) => {
  const [ip, setIp] = useState('');
  const [name, setName] = useState('Harman Kardon');
  const [isScanning, setIsScanning] = useState(false);
  const [scanStatus, setScanStatus] = useState('');
  const [discoveredDevices, setDiscoveredDevices] = useState([]);

  useEffect(() => {
    loadStereoConfig().then((config) => {
      setIp(config.ip);
      setName(config.name);
    });
  }, []);

  const saveAndContinue = async () => {
    await saveStereoConfig({ name, ip, deviceType: 'avr', zone: 'Main Zone' });
    navigation.navigate('Remote');
  };

  const findStereo = async () => {
    setIsScanning(true);
    setDiscoveredDevices([]);
    setScanStatus('Looking for your Wi-Fi network...');

    try {
      const result = await discoverStereos({
        onProgress: ({ scanned, total, subnetPrefix }) => {
          setScanStatus(`Scanning ${subnetPrefix}.x (${scanned}/${total})...`);
        },
      });

      setDiscoveredDevices(result.devices);
      setScanStatus(
        result.devices.length
          ? `Found ${result.devices.length} candidate${result.devices.length === 1 ? '' : 's'} on ${result.subnetPrefix}.x`
          : `No stereo found on ${result.subnetPrefix}.x`,
      );
    } catch (error) {
      setScanStatus('');
      Alert.alert('Discovery failed', error.message);
    } finally {
      setIsScanning(false);
    }
  };

  const selectDiscoveredDevice = (device) => {
    setIp(device.ip);
    setName(device.name);
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Stereo Setup</Text>
      <Button title={isScanning ? 'Scanning...' : 'Find Stereo'} onPress={findStereo} disabled={isScanning} />
      {!!scanStatus && <Text style={styles.scanStatus}>{scanStatus}</Text>}
      <FlatList
        data={discoveredDevices}
        keyExtractor={(item) => item.id}
        style={styles.results}
        renderItem={({ item }) => (
          <View style={styles.resultItem}>
            <Text style={styles.resultTitle}>{item.name}</Text>
            <Text style={styles.resultSubtitle}>{item.ip}:{item.port}</Text>
            <Button title="Use This Stereo" onPress={() => selectDiscoveredDevice(item)} />
          </View>
        )}
      />
      <Text style={styles.label}>Name</Text>
      <TextInput style={styles.input} value={name} onChangeText={setName} />
      <Text style={styles.label}>IP Address</Text>
      <TextInput
        style={styles.input}
        value={ip}
        onChangeText={setIp}
        placeholder="192.168.1.242"
        autoCapitalize="none"
        keyboardType="numbers-and-punctuation"
      />
      <Button title="Save & Open Remote" onPress={saveAndContinue} disabled={!ip} />
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24, justifyContent: 'center' },
  title: { fontSize: 22, fontWeight: '600', marginBottom: 24 },
  scanStatus: { marginTop: 12, marginBottom: 8, color: '#666' },
  results: { maxHeight: 180, marginBottom: 16 },
  resultItem: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    marginBottom: 8,
  },
  resultTitle: { fontWeight: '600', marginBottom: 4 },
  resultSubtitle: { color: '#666', marginBottom: 8 },
  label: { marginBottom: 6, color: '#444' },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    padding: 12,
    marginBottom: 16,
  },
});

export default DeviceSetupScreen;
