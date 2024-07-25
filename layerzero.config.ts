import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

const baseContract: OmniPointHardhat = {
    eid: EndpointId.BASESEP_V2_TESTNET,
    contractName: 'LaunchToken',
}

const zoraContract: OmniPointHardhat = {
    eid: EndpointId.ZORASEP_V2_TESTNET,
    contractName: 'RewardsDistributor',
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: baseContract,
        },
        {
            contract: zoraContract,
        },
    ],
    connections: [
        {
            from: zoraContract,
            to: baseContract,
        },
        {
            from: baseContract,
            to: zoraContract,
        },
    ],
}

export default config
