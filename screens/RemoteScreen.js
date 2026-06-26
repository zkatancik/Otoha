import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Alert, ScrollView, Switch, TextInput } from 'react-native';
import Button from '../components/Button';
import { loadStereoConfig } from '../services/stereoConfig';
import { runRawStereoCommand, runStereoAction } from '../services/stereo';

const RemoteScreen = ({ navigation }) => {
  const [config, setConfig] = useState(null);
  const [rawCommand, setRawCommand] = useState('harman-volume');
  const [rawParam, setRawParam] = useState('');
  const [rawHasResponse, setRawHasResponse] = useState(false);

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

  const sendRawCommand = async () => {
    try {
      const response = await runRawStereoCommand({
        name: rawCommand,
        param: rawParam,
        hasResponse: rawHasResponse,
      });
      Alert.alert(
        'Raw command sent',
        response ? `Response:\n${response}` : 'The command was sent. Watch the receiver for changes.',
      );
    } catch (error) {
      Alert.alert('Raw command failed', error.message);
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
    <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
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

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Experimental Raw Command</Text>
        <Text style={styles.helpText}>
          Sends a custom HK wire command to {config.zone}. Unsupported commands may fail silently.
        </Text>
        <Text style={styles.label}>Command name</Text>
        <TextInput
          style={styles.input}
          value={rawCommand}
          onChangeText={setRawCommand}
          placeholder="harman-volume"
          autoCapitalize="none"
          autoCorrect={false}
        />
        <Text style={styles.label}>Param</Text>
        <TextInput
          style={styles.input}
          value={rawParam}
          onChangeText={setRawParam}
          placeholder="Off, Low, Medium, High, Max..."
          autoCapitalize="none"
          autoCorrect={false}
        />
        <View style={styles.switchRow}>
          <Text style={styles.label}>Wait for response</Text>
          <Switch value={rawHasResponse} onValueChange={setRawHasResponse} />
        </View>
        <Button title="Send Raw Command" onPress={sendRawCommand} />
      </View>

      <Button title="Test Connection" onPress={testConnection} />
      <Button title="Change Device" onPress={() => navigation.navigate('Setup')} />
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: { flexGrow: 1, padding: 24, justifyContent: 'center' },
  title: { fontSize: 22, fontWeight: '600', textAlign: 'center' },
  subtitle: { textAlign: 'center', color: '#666', marginBottom: 32 },
  section: { marginBottom: 24 },
  sectionTitle: { fontSize: 16, fontWeight: '500', marginBottom: 8 },
  helpText: { color: '#666', marginBottom: 12 },
  label: { marginBottom: 6, color: '#444' },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    padding: 12,
    marginBottom: 12,
  },
  row: { flexDirection: 'row', justifyContent: 'center' },
  switchRow: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
});

export default RemoteScreen;
