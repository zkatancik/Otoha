import { PhoneAccess } from '../server/phone-access.js';
const code = new PhoneAccess().issue();
console.log(
  'In Otoha Settings, turn on “Access outside the home”. Enter this code and tap “Pair this iPhone”. It expires in 10 minutes.\n\n' + code + '\n',
);
