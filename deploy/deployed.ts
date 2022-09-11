export class DeployedContracts {
  validatorManager: string = '';
  rai20Factory: string = '';
  rai721Factory: string = '';
  core: string = '';
  rai20InitCodeHash: string = '';
  rai721InitCodeHash: string = '';
}

export const INVALID_DEPLOYED_ADDRESS = '0x0000000000000000000000000000000000000000';

export const BSC_CONTRACTS: DeployedContracts = {
  validatorManager: '0x0000000000000000000000000000000000000000',
  rai20Factory: '0x0000000000000000000000000000000000000000',
  rai721Factory: '0x0000000000000000000000000000000000000000',
  core: '0x0000000000000000000000000000000000000000',
  rai20InitCodeHash: '0x0000000000000000000000000000000000000000',
  rai721InitCodeHash: '0x0000000000000000000000000000000000000000',
}

export const ETH_CONTRACTS: DeployedContracts = {
  validatorManager: '0x0000000000000000000000000000000000000000',
  rai20Factory: '0x0000000000000000000000000000000000000000',
  rai721Factory: '0x0000000000000000000000000000000000000000',
  core: '0x0000000000000000000000000000000000000000',
  rai20InitCodeHash: '0x0000000000000000000000000000000000000000',
  rai721InitCodeHash: '0x0000000000000000000000000000000000000000',
}


// testnet
export const BSC_TEST_CONTRACTS: DeployedContracts = {
  validatorManager: '0x4f428DD655246e5e5a30e7853D6F575D7eE74449',
  rai20Factory: '0x65abfcfe3c57A421E42593EEF49722997D72Fd07',
  rai721Factory: '0x99787450483d49EbD7090e2D03DCB6b255d6459e',
  core: '0x68CF8517a569565F0B30f8856F0555d55d539307',
  rai20InitCodeHash: '0x1b5c33b47717fc77f055505ae58980aed61f22119de91b6858edcadf580957a7',
  rai721InitCodeHash: '0xc347358fe2a350a876ea77206abccd32f51c5db2732cfdbed075dd70d9adb196',
}

export const GOERLI_CONTRACTS: DeployedContracts = {
  validatorManager: '0x7DeeFB52862680C0eA9680C676697c2B11951516',
  rai20Factory: '0x8E58F54073e02f4446653469C7fEE7e058a32Bbb',
  rai721Factory: '0x9048388ceDf0754A5D1Eb8a401Ad06d8fbAd0907',
  core: '0xfC113A7B68074642cA2FC74733A9BF325C045F14',
  rai20InitCodeHash: '0x1b5c33b47717fc77f055505ae58980aed61f22119de91b6858edcadf580957a7',
  rai721InitCodeHash: '0xc347358fe2a350a876ea77206abccd32f51c5db2732cfdbed075dd70d9adb196',
}