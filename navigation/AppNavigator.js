import React, { useState, useEffect } from 'react';
import { createStackNavigator } from '@react-navigation/stack';
import AsyncStorage from '@react-native-async-storage/async-storage';
import DeviceSelection from '../components/DeviceSelection';
import RemoteControl from '../components/RemoteControl';

const Stack = createStackNavigator();

export default function AppNavigator() {
  const [defaultDevice, setDefaultDevice] = useState(null);

  useEffect(() => {
    const getDefaultDevice = async () => {
      const device = await AsyncStorage.getItem('defaultDevice');
      if (device) {
        setDefaultDevice(device);
      }
    };
    getDefaultDevice();
  }, []);

  return (
    <Stack.Navigator>
      <Stack.Screen name="DeviceSelection" component={DeviceSelection} />
      <Stack.Screen name="RemoteControl">
        {props => <RemoteControl {...props} device={defaultDevice} />}
      </Stack.Screen>
    </Stack.Navigator>
  );
}
