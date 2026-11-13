import abilityTest from './Ability.test';
import utilsTest from './Utils.test';
import wsServiceTest from './WsService.test';
import wsReconnectTest from './WsServiceReconnect.test';
import cryptoServiceTest from './CryptoService.test';

export default function testsuite() {
  abilityTest();
  utilsTest();
  wsServiceTest();
  wsReconnectTest();
  cryptoServiceTest();
}