import React from 'react';
import { createStackNavigator } from '@react-navigation/stack';
import DeviceSetupScreen from '../screens/DeviceSetupScreen';
import RemoteScreen from '../screens/RemoteScreen';

const Stack = createStackNavigator();

export default function AppNavigator() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="Setup" component={DeviceSetupScreen} options={{ title: 'Setup' }} />
      <Stack.Screen name="Remote" component={RemoteScreen} options={{ title: 'Remote' }} />
    </Stack.Navigator>
  );
}
