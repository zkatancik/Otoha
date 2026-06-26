import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Alert } from 'react-native';
import Button from '../components/Button';
import { loadStereoConfig } from '../services/stereoConfig';
import { runStereoAction } from '../services/stereo';

const RemoteScreen = ({ navigation }) => {
  const [config, setConfig] = useState(null);

  useEffect(() => {
    loadStereoConfig().then(setConfig);
  }, []);

  const send = async (action) => {
    try {
      await runStereoAction(action);
    } catch (error) {
      Alert.alert('Command failed', error.message);
    }
  };

  const testConnection = async () => {
    try {
      await runStereoAction('heartAlive');
      Alert.alert('Connection OK', 'The stereo responded to heartAlive.');
    } catch (error) {
      Alert.alert('Connection failed', error.message);
    }
  };

  if (!config) {
    return null;
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{config.name}</Text>
      <Text style={styles.subtitle}>{config.ip || 'No IP configured'}</Text>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Volume</Text>
        <View style={styles.row}>
          <Button title="Vol −" onPress={() => send('volumeDown')} />
          <Button title="Mute" onPress={() => send('muteToggle')} />
          <Button title="Vol +" onPress={() => send('volumeUp')} />
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Power</Text>
        <View style={styles.row}>
          <Button title="On" onPress={() => send('on')} />
          <Button title="Off" onPress={() => send('off')} />
        </View>
      </View>

      <Button title="Test Connection" onPress={testConnection} />
      <Button title="Change Device" onPress={() => navigation.navigate('Setup')} />
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, padding: 24, justifyContent: 'center' },
  title: { fontSize: 22, fontWeight: '600', textAlign: 'center' },
  subtitle: { textAlign: 'center', color: '#666', marginBottom: 32 },
  section: { marginBottom: 24 },
  sectionTitle: { fontSize: 16, fontWeight: '500', marginBottom: 8 },
  row: { flexDirection: 'row', justifyContent: 'center' },
});

export default RemoteScreen;
