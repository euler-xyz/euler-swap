let chains = [
  //// PRODUCTION

  {
    chainId: 31337,
    name: 'dev',
    safeBaseUrl: 'https://app.safe.global',
    safeAddressPrefix: 'dev',
    status: 'beta',
  },
];



const fs = require("node:fs");

for (let c of chains) {
    let addrsDir = `./script/dev-ctx/addresses/${c.chainId}/`;

    c.addresses = {};

    for (const file of fs.readdirSync(addrsDir)) {
        if (!file.endsWith('Addresses.json')) continue;
        let section = file.replace(/Addresses[.]json$/, 'Addrs');
        section = (section[0] + '').toLowerCase() + section.substr(1);
        c.addresses[section] = JSON.parse(fs.readFileSync(`${addrsDir}/${file}`).toString());
    }
}

fs.writeFileSync('./script/dev-ctx/EulerChains.json', JSON.stringify(chains));
