import React from 'react';
import { View, StyleSheet, Text } from 'react-native';
import Button from './Button';
import api from '../services/api';

const RemoteControl = ({ device }) => {
  const handlePress = (action) => {
    api[action]();
  };

  return (
    <View style={styles.container}>
      <Text>Controlling {device}</Text>
      <View style={styles.buttonRow}>
        <Button title="Up" onPress={() => handlePress('up')} />
      </View>
      <View style={styles.buttonRow}>
        <Button title="Left" onPress={() => handlePress('left')} />
        <Button title="OK" onPress={() => handlePress('ok')} />
        <Button title="Right" onPress={() => handlePress('right')} />
      </View>
      <View style={styles.buttonRow}>
        <Button title="Down" onPress={() => handlePress('down')} />
      </View>
      <View style={styles.buttonRow}>
        <Button title="Play" onPress={() => handlePress('play')} />
        <Button title="Pause" onPress={() => handlePress('pause')} />
      </View>
      {/* Add more buttons as needed */}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  buttonRow: {
    flexDirection: 'row',
    margin: 10,
  },
});

export default RemoteControl;
