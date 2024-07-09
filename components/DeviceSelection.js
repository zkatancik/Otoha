import React from 'react';
import { View, Text, Button, FlatList } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

const devices = ['HK 3770']; // Example devices

const DeviceSelection = ({ navigation }) => {
  const selectDevice = async (device) => {
    await AsyncStorage.setItem('defaultDevice', device);
    navigation.navigate('RemoteControl', { device });
  };

  return (
    <View>
      <Text>Select a Device</Text>
      <FlatList
        data={devices}
        renderItem={({ item }) => (
          <Button title={item} onPress={() => selectDevice(item)} />
        )}
        keyExtractor={(item) => item}
      />
    </View>
  );
};

export default DeviceSelection;
